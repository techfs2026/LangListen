import { useRef, useCallback, useEffect } from "react";
import type { ChannelData, RenderData, WaveformColors, GlResources } from "./types";

// ── shaders ──────────────────────────────────────────────────────────────────

const VERT_SRC = `#version 300 es
precision highp float;
layout(location = 0) in vec2 aPos;
uniform mat4 uMatrix;
uniform float uPointSize;
void main() {
  gl_Position = uMatrix * vec4(aPos, 0.0, 1.0);
  gl_PointSize = uPointSize;
}`;

const FRAG_SRC = `#version 300 es
precision mediump float;
uniform vec4 uColor;
out vec4 fragColor;
void main() {
  fragColor = uColor;
}`;

// ── 渲染参数 ─────────────────────────────────────────────────────────────────

export interface RenderParams {
  data: RenderData | null;
  playhead: number;
  dragRange: [number, number] | null;
  regions: Array<{ start: number; end: number; selected?: boolean; overlapping?: boolean }>;
  colors: WaveformColors;
  /** 正在回环的区间（归一化，相对于当前 viewRange），高亮显示 */
  loopRange?: [number, number] | null;
}

interface UseWebGLReturn {
  canvasRef: React.RefObject<HTMLCanvasElement>;
  render: (params: RenderParams) => void;
}

export function useWebGL(): UseWebGLReturn {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const glRef = useRef<GlResources | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const gl = canvas.getContext("webgl2", {
      alpha: false,
      antialias: true,
      depth: false,
      stencil: false,
      powerPreference: "high-performance",
    });
    if (!gl) {
      console.error("WebGL2 not available");
      return;
    }

    const program = createProgram(gl, VERT_SRC, FRAG_SRC);
    if (!program) return;

    const vao = gl.createVertexArray()!;
    const vbo = gl.createBuffer()!;

    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 8, 0);
    gl.bindVertexArray(null);

    glRef.current = { gl, program, vao, vbo };

    return () => {
      gl.deleteProgram(program);
      gl.deleteVertexArray(vao);
      gl.deleteBuffer(vbo);
      glRef.current = null;
    };
  }, []);

  const render = useCallback((params: RenderParams) => {
    const res = glRef.current;
    const canvas = canvasRef.current;
    if (!res || !canvas) return;

    const { gl, program, vao, vbo } = res;
    const { data, playhead, dragRange, regions, colors, loopRange } = params;

    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth * dpr;
    const h = canvas.clientHeight * dpr;
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }

    gl.viewport(0, 0, w, h);
    const bg = hexToVec4(colors.background);
    gl.clearColor(bg[0], bg[1], bg[2], 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT);

    gl.useProgram(program);
    gl.bindVertexArray(vao);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    const uMatrix = gl.getUniformLocation(program, "uMatrix");
    const uColor = gl.getUniformLocation(program, "uColor");
    const uPointSize = gl.getUniformLocation(program, "uPointSize");
    gl.uniformMatrix4fv(uMatrix, false, orthoMatrix(w, h));
    gl.uniform1f(uPointSize, 1.0);

    // ── 0. 书桌纸面网格 ───────────────────────────────────────────────────
    drawStudyPaper(gl, vbo, uColor, w, h, colors);

    // ── 1. 回环高亮区间 ───────────────────────────────────────────────────
    if (loopRange) {
      const [ls, le] = loopRange;
      const lx = ls * w;
      const rx = le * w;
      // 淡黄绿色背景，区别于 label 的蓝色和 selection 的黄色
      gl.uniform4f(uColor, 0.18, 0.8, 0.44, 0.12);
      uploadAndDraw(gl, vbo, makeRect(lx, 0, rx, h), gl.TRIANGLES);
      // 两侧竖线
      gl.uniform4f(uColor, 0.18, 0.8, 0.44, 0.7);
      uploadAndDraw(gl, vbo, new Float32Array([lx, 0, lx, h, rx, 0, rx, h]), gl.LINES);
    }

    // ── 2. 区域底色 / 拖拽选区 ───────────────────────────────────────────
    drawRegionsAndSelection(gl, vbo, uColor, w, h, regions, dragRange, colors);

    // ── 3. 波形 ───────────────────────────────────────────────────────────
    if (data && data.channels.length > 0) {
      const channelCount = data.channels.length;
      const laneH = h / channelCount;
      const laneAmpScale = laneH * 0.42;
      for (let i = 0; i < channelCount; i++) {
        const midY = laneH * (i + 0.5);
        drawChannel(
          gl,
          vbo,
          uColor,
          uPointSize,
          data.channels[i],
          0,
          w,
          midY,
          laneAmpScale,
          colors,
        );
      }

      if (channelCount === 2) {
        const dc = hexToVec4(colors.channelDivider ?? "#D1D5DB");
        gl.uniform4f(uColor, dc[0], dc[1], dc[2], 0.6);
        uploadAndDraw(gl, vbo, new Float32Array([0, laneH, w, laneH]), gl.LINES);
      }
    }

    // ── 4. 播放头 ─────────────────────────────────────────────────────────
    if (playhead >= 0 && playhead <= 1) {
      const halfW = 1.5; // 3px 宽，比原来更醒目
      // 夹紧到画布内，保证 playhead=0（刚加载在最左缘）时整条仍可见
      const px = Math.min(Math.max(playhead * w, halfW), w - halfW);
      const phc = hexToVec4(colors.playhead);
      gl.uniform4f(uColor, phc[0], phc[1], phc[2], 1.0);
      uploadAndDraw(gl, vbo, makeRect(px - halfW, 0, px + halfW, h), gl.TRIANGLES);
      uploadAndDraw(gl, vbo, new Float32Array([px, 24, px - 7, 13, px + 7, 13]), gl.TRIANGLES);
    }

    gl.bindVertexArray(null);
    gl.disable(gl.BLEND);
  }, []);

  return { canvasRef, render };
}

// ── 标签 / 拖拽选区 ──────────────────────────────────────────────────────────

function drawStudyPaper(
  gl: WebGL2RenderingContext,
  vbo: WebGLBuffer,
  uColor: WebGLUniformLocation | null,
  w: number,
  h: number,
  colors: WaveformColors,
) {
  const ink = hexToVec4(colors.centerLine ?? "#1A2744");
  gl.uniform4f(uColor, ink[0], ink[1], ink[2], 0.055);

  const rowHeight = 42 * (window.devicePixelRatio || 1);
  const rowLines: number[] = [];
  for (let y = rowHeight; y < h; y += rowHeight) {
    rowLines.push(0, y, w, y);
  }
  if (rowLines.length > 0) {
    uploadAndDraw(gl, vbo, new Float32Array(rowLines), gl.LINES);
  }

  gl.uniform4f(uColor, ink[0], ink[1], ink[2], 0.075);
  const colWidth = Math.max(72, Math.min(128, w / 12));
  const colLines: number[] = [];
  for (let x = colWidth; x < w; x += colWidth) {
    colLines.push(x, 0, x, h);
  }
  if (colLines.length > 0) {
    uploadAndDraw(gl, vbo, new Float32Array(colLines), gl.LINES);
  }
}

function drawRegionsAndSelection(
  gl: WebGL2RenderingContext,
  vbo: WebGLBuffer,
  uColor: WebGLUniformLocation | null,
  w: number,
  h: number,
  regions: Array<{ start: number; end: number; selected?: boolean; overlapping?: boolean }>,
  dragRange: [number, number] | null,
  colors: WaveformColors,
) {
  if (regions.length > 0) {
    const fill = hexToVec4(colors.regionFill);
    const border = hexToVec4(colors.regionBorder);
    for (const region of regions) {
      const lx = region.start * w;
      const rx = region.end * w;
      const top = 14 * (window.devicePixelRatio || 1);
      const bottom = h - top;
      if (region.selected) {
        gl.uniform4f(uColor, fill[0], fill[1], fill[2], 0.54);
        uploadAndDraw(gl, vbo, makeRect(lx, top, rx, bottom), gl.TRIANGLES);
        gl.uniform4f(uColor, border[0], border[1], border[2], 0.88);
        uploadAndDraw(
          gl,
          vbo,
          new Float32Array([
            lx,
            top,
            lx,
            bottom,
            rx,
            top,
            rx,
            bottom,
            lx,
            top,
            rx,
            top,
            lx,
            bottom,
            rx,
            bottom,
          ]),
          gl.LINES,
        );
      } else if (region.overlapping) {
        // 重叠：红色填充 + 红色边框
        gl.uniform4f(uColor, 0.95, 0.2, 0.2, 0.25);
        uploadAndDraw(gl, vbo, makeRect(lx, top, rx, bottom), gl.TRIANGLES);
        gl.uniform4f(uColor, 0.85, 0.1, 0.1, 0.9); // 深红
        uploadAndDraw(
          gl,
          vbo,
          new Float32Array([lx, top, lx, bottom, rx, top, rx, bottom]),
          gl.LINES,
        );
      } else {
        gl.uniform4f(uColor, fill[0], fill[1], fill[2], 0.3);
        uploadAndDraw(gl, vbo, makeRect(lx, top, rx, bottom), gl.TRIANGLES);
        gl.uniform4f(uColor, border[0], border[1], border[2], 0.7);
        uploadAndDraw(
          gl,
          vbo,
          new Float32Array([lx, top, lx, bottom, rx, top, rx, bottom]),
          gl.LINES,
        );
      }
    }
  }

  if (dragRange) {
    const [ds, de] = dragRange;
    const lx = ds * w;
    const rx = de * w;
    const sc = hexToVec4(colors.selection);
    const top = 14 * (window.devicePixelRatio || 1);
    const bottom = h - top;
    gl.uniform4f(uColor, sc[0], sc[1], sc[2], 0.2);
    uploadAndDraw(gl, vbo, makeRect(lx, top, rx, bottom), gl.TRIANGLES);
    gl.uniform4f(uColor, sc[0], sc[1], sc[2], 0.7);
    uploadAndDraw(gl, vbo, new Float32Array([lx, top, lx, bottom, rx, top, rx, bottom]), gl.LINES);
  }
}

// ── 单声道波形渲染 ────────────────────────────────────────────────────────────

function drawChannel(
  gl: WebGL2RenderingContext,
  vbo: WebGLBuffer,
  uColor: WebGLUniformLocation | null,
  uPointSize: WebGLUniformLocation | null,
  ch: ChannelData,
  xStart: number,
  xEnd: number,
  midY: number,
  ampScale: number,
  colors: WaveformColors,
) {
  const cc = hexToVec4(colors.centerLine ?? "#1F2937");
  gl.uniform4f(uColor, cc[0], cc[1], cc[2], 0.5);
  uploadAndDraw(gl, vbo, new Float32Array([xStart, midY, xEnd, midY]), gl.LINES);

  switch (ch.kind) {
    case "envelope":
      drawEnvelope(gl, vbo, uColor, ch.peaks, xStart, xEnd, midY, ampScale, colors);
      break;
    case "polyline":
      drawPolyline(gl, vbo, uColor, ch.points, xStart, xEnd, midY, ampScale, colors, false);
      break;
    case "stem":
      drawPolyline(gl, vbo, uColor, ch.points, xStart, xEnd, midY, ampScale, colors, true);
      gl.uniform1f(uPointSize, 4.0);
      drawSamplePoints(gl, vbo, uColor, ch.points, xStart, xEnd, midY, ampScale, colors);
      gl.uniform1f(uPointSize, 1.0);
      break;
  }
}

function drawEnvelope(
  gl: WebGL2RenderingContext,
  vbo: WebGLBuffer,
  uColor: WebGLUniformLocation | null,
  peaks: Array<{ min: number; max: number; rms: number }>,
  xStart: number,
  xEnd: number,
  midY: number,
  ampScale: number,
  colors: WaveformColors,
) {
  const n = peaks.length;
  if (n === 0) return;
  const xRange = xEnd - xStart;

  const envVerts = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const x = xStart + (i / Math.max(1, n - 1)) * xRange;
    const p = peaks[i];
    envVerts[i * 4] = x;
    envVerts[i * 4 + 1] = midY - p.max * ampScale;
    envVerts[i * 4 + 2] = x;
    envVerts[i * 4 + 3] = midY - p.min * ampScale;
  }
  const wc = hexToVec4(colors.wave);
  gl.uniform4f(uColor, wc[0], wc[1], wc[2], 1.0);
  uploadAndDraw(gl, vbo, envVerts, gl.TRIANGLE_STRIP);

  const rmsVerts = new Float32Array(n * 4);
  for (let i = 0; i < n; i++) {
    const x = xStart + (i / Math.max(1, n - 1)) * xRange;
    const r = peaks[i].rms;
    rmsVerts[i * 4] = x;
    rmsVerts[i * 4 + 1] = midY - r * ampScale;
    rmsVerts[i * 4 + 2] = x;
    rmsVerts[i * 4 + 3] = midY + r * ampScale;
  }
  const rc = hexToVec4(colors.waveRms);
  gl.uniform4f(uColor, rc[0], rc[1], rc[2], 1.0);
  uploadAndDraw(gl, vbo, rmsVerts, gl.TRIANGLE_STRIP);
}

function drawPolyline(
  gl: WebGL2RenderingContext,
  vbo: WebGLBuffer,
  uColor: WebGLUniformLocation | null,
  points: Array<[number, number]>,
  xStart: number,
  xEnd: number,
  midY: number,
  ampScale: number,
  colors: WaveformColors,
  _isStem: boolean,
) {
  const n = points.length;
  if (n === 0) return;

  const verts = new Float32Array(n * 2);
  for (let i = 0; i < n; i++) {
    verts[i * 2] = points[i][0];
    verts[i * 2 + 1] = midY - points[i][1] * ampScale;
  }

  const rc = hexToVec4(colors.waveRms);
  gl.uniform4f(uColor, rc[0], rc[1], rc[2], 0.95);
  uploadAndDraw(gl, vbo, verts, gl.LINE_STRIP);

  void xStart;
  void xEnd;
  void _isStem;
}

function drawSamplePoints(
  gl: WebGL2RenderingContext,
  vbo: WebGLBuffer,
  uColor: WebGLUniformLocation | null,
  points: Array<[number, number]>,
  xStart: number,
  xEnd: number,
  midY: number,
  ampScale: number,
  colors: WaveformColors,
) {
  const n = points.length;
  if (n === 0) return;

  const verts = new Float32Array(n * 2);
  for (let i = 0; i < n; i++) {
    verts[i * 2] = points[i][0];
    verts[i * 2 + 1] = midY - points[i][1] * ampScale;
  }
  const rc = hexToVec4(colors.waveRms);
  gl.uniform4f(uColor, rc[0], rc[1], rc[2], 1.0);
  uploadAndDraw(gl, vbo, verts, gl.POINTS);

  void xStart;
  void xEnd;
}

// ── WebGL 工具函数 ──────────────────────────────────────────────────────────

function createProgram(gl: WebGL2RenderingContext, vs: string, fs: string) {
  const vert = compileShader(gl, gl.VERTEX_SHADER, vs);
  const frag = compileShader(gl, gl.FRAGMENT_SHADER, fs);
  if (!vert || !frag) return null;
  const p = gl.createProgram()!;
  gl.attachShader(p, vert);
  gl.attachShader(p, frag);
  gl.linkProgram(p);
  gl.deleteShader(vert);
  gl.deleteShader(frag);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
    console.error("Link error:", gl.getProgramInfoLog(p));
    return null;
  }
  return p;
}

function compileShader(gl: WebGL2RenderingContext, type: number, src: string) {
  const s = gl.createShader(type)!;
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    console.error("Compile error:", gl.getShaderInfoLog(s));
    gl.deleteShader(s);
    return null;
  }
  return s;
}

function uploadAndDraw(
  gl: WebGL2RenderingContext,
  vbo: WebGLBuffer,
  data: Float32Array,
  mode: number,
) {
  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  gl.bufferData(gl.ARRAY_BUFFER, data, gl.DYNAMIC_DRAW);
  gl.drawArrays(mode, 0, data.length / 2);
}

function makeRect(x0: number, y0: number, x1: number, y1: number): Float32Array {
  return new Float32Array([x0, y0, x1, y0, x0, y1, x1, y0, x1, y1, x0, y1]);
}

function orthoMatrix(w: number, h: number): Float32Array {
  return new Float32Array([2 / w, 0, 0, 0, 0, -2 / h, 0, 0, 0, 0, -1, 0, -1, 1, 0, 1]);
}

function hexToVec4(hex: string): [number, number, number, number] {
  const c = hex.replace("#", "");
  return [
    parseInt(c.slice(0, 2), 16) / 255,
    parseInt(c.slice(2, 4), 16) / 255,
    parseInt(c.slice(4, 6), 16) / 255,
    c.length === 8 ? parseInt(c.slice(6, 8), 16) / 255 : 1.0,
  ];
}
