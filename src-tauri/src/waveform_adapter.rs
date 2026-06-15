use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use tauri::State;
use waveform::{
    ChannelMode, ChannelRenderData, DecodeOptions, RenderMode, ViewRange, Waveform,
    WaveformOptions, MAX_QUERY_PIXEL_WIDTH,
};

pub struct WaveformSessions {
    next_id: AtomicU64,
    sessions: Mutex<HashMap<u64, Arc<Waveform>>>,
}

impl WaveformSessions {
    pub fn new() -> Self {
        Self {
            next_id: AtomicU64::new(1),
            sessions: Mutex::new(HashMap::new()),
        }
    }

    fn insert(&self, waveform: Waveform) -> u64 {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        self.sessions.lock().unwrap().insert(id, Arc::new(waveform));
        id
    }

    fn get(&self, id: u64) -> Option<Arc<Waveform>> {
        self.sessions.lock().unwrap().get(&id).cloned()
    }

    fn remove(&self, id: u64) -> bool {
        self.sessions.lock().unwrap().remove(&id).is_some()
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WaveformOpenOptionsDto {
    pub sample_rate: Option<u32>,
    pub channel_mode: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WaveformOpenRequestDto {
    pub path: String,
    pub options: Option<WaveformOpenOptionsDto>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WaveformSessionDto {
    pub session_id: u64,
    pub metadata: WaveformMetadataDto,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WaveformMetadataDto {
    pub duration: f64,
    pub sample_rate: u32,
    pub level_count: usize,
    pub channel_count: usize,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WaveformQueryDto {
    pub session_id: u64,
    pub view: WaveformViewDto,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WaveformViewDto {
    pub start_sec: f64,
    pub end_sec: f64,
    pub pixel_width: usize,
}

#[derive(Debug, Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum ChannelDataDto {
    Envelope { peaks: Vec<PeakDto> },
    Polyline { points: Vec<[f32; 2]> },
    Stem { points: Vec<[f32; 2]> },
}

#[derive(Debug, Serialize)]
pub struct PeakDto {
    pub min: f32,
    pub max: f32,
    pub rms: f32,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RenderDataDto {
    pub mode: &'static str,
    pub channels: Vec<ChannelDataDto>,
    pub pixel_width: usize,
}

#[tauri::command]
pub fn waveform_open(
    request: WaveformOpenRequestDto,
    sessions: State<WaveformSessions>,
) -> Result<WaveformSessionDto, String> {
    let decode = decode_options(request.options)?;
    let waveform = Waveform::open(
        &request.path,
        WaveformOptions {
            decode,
            ..WaveformOptions::default()
        },
    )
    .map_err(|error| error.to_string())?;
    let metadata = waveform.metadata();
    let session_id = sessions.insert(waveform);

    Ok(WaveformSessionDto {
        session_id,
        metadata: WaveformMetadataDto {
            duration: metadata.duration_secs,
            sample_rate: metadata.sample_rate,
            level_count: metadata.level_count,
            channel_count: metadata.channel_count,
        },
    })
}

#[tauri::command]
pub fn waveform_query(
    request: WaveformQueryDto,
    sessions: State<WaveformSessions>,
) -> Result<RenderDataDto, String> {
    let waveform = sessions
        .get(request.session_id)
        .ok_or_else(|| format!("waveform session {} not found", request.session_id))?;
    validate_query(&request.view)?;
    let duration = waveform.metadata().duration_secs;
    let view = ViewRange {
        start_sec: request.view.start_sec.max(0.0),
        end_sec: request.view.end_sec.min(duration),
        pixel_width: request.view.pixel_width,
    };
    if view.end_sec <= view.start_sec {
        return Err("waveform view does not overlap the audio".into());
    }
    let render = waveform.query(view).map_err(|error| error.to_string())?;
    let mode = match render.mode {
        RenderMode::Envelope => "envelope",
        RenderMode::Polyline => "polyline",
        RenderMode::Stem => "stem",
    };
    let channels = render
        .channels
        .into_iter()
        .map(|channel| match channel {
            ChannelRenderData::Envelope(peaks) => ChannelDataDto::Envelope {
                peaks: peaks
                    .into_iter()
                    .map(|peak| PeakDto {
                        min: peak.min,
                        max: peak.max,
                        rms: peak.rms,
                    })
                    .collect(),
            },
            ChannelRenderData::Polyline(points) => ChannelDataDto::Polyline {
                points: points.into_iter().map(|(x, y)| [x, y]).collect(),
            },
            ChannelRenderData::Stem(points) => ChannelDataDto::Stem {
                points: points.into_iter().map(|(x, y)| [x, y]).collect(),
            },
        })
        .collect();

    Ok(RenderDataDto {
        mode,
        channels,
        pixel_width: request.view.pixel_width,
    })
}

#[tauri::command]
pub fn waveform_close(session_id: u64, sessions: State<WaveformSessions>) -> Result<(), String> {
    sessions.remove(session_id);
    Ok(())
}

fn decode_options(options: Option<WaveformOpenOptionsDto>) -> Result<DecodeOptions, String> {
    let Some(options) = options else {
        return Ok(DecodeOptions::default());
    };
    let sample_rate = options.sample_rate.unwrap_or(22_050);
    if sample_rate == 0 {
        return Err("sampleRate must be greater than zero".into());
    }
    let channel_mode = match options.channel_mode.as_deref().unwrap_or("auto") {
        "auto" => ChannelMode::Auto,
        "mono" => ChannelMode::Mono,
        "stereo" => ChannelMode::Stereo,
        "preserve" => ChannelMode::Preserve,
        value => return Err(format!("unsupported channelMode: {value}")),
    };
    Ok(DecodeOptions {
        sample_rate,
        channel_mode,
    })
}

fn validate_query(view: &WaveformViewDto) -> Result<(), String> {
    if !view.start_sec.is_finite() || !view.end_sec.is_finite() {
        return Err("waveform view times must be finite".into());
    }
    if view.end_sec <= view.start_sec {
        return Err("waveform view endSec must be greater than startSec".into());
    }
    if view.pixel_width == 0 || view.pixel_width > MAX_QUERY_PIXEL_WIDTH {
        return Err(format!(
            "pixelWidth must be between 1 and {MAX_QUERY_PIXEL_WIDTH}"
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use waveform::{AudioBuffer, BuildOptions};

    fn waveform(value: f32) -> Waveform {
        Waveform::from_audio_buffer(
            AudioBuffer::new(vec![vec![value; 1_000]], 1_000).unwrap(),
            BuildOptions::default(),
        )
    }

    #[test]
    fn registry_keeps_sessions_independent() {
        let sessions = WaveformSessions::new();
        let first = sessions.insert(waveform(0.25));
        let second = sessions.insert(waveform(0.75));

        assert_ne!(first, second);
        assert!(sessions.get(first).is_some());
        assert!(sessions.get(second).is_some());
        assert!(sessions.remove(first));
        assert!(sessions.get(first).is_none());
        assert!(sessions.get(second).is_some());
    }

    #[test]
    fn validates_decoder_options() {
        assert!(decode_options(Some(WaveformOpenOptionsDto {
            sample_rate: Some(0),
            channel_mode: None,
        }))
        .is_err());
        assert!(decode_options(Some(WaveformOpenOptionsDto {
            sample_rate: None,
            channel_mode: Some("unknown".into()),
        }))
        .is_err());
    }

    #[test]
    fn validates_query_limits() {
        assert!(validate_query(&WaveformViewDto {
            start_sec: 0.0,
            end_sec: 1.0,
            pixel_width: MAX_QUERY_PIXEL_WIDTH,
        })
        .is_ok());
        assert!(validate_query(&WaveformViewDto {
            start_sec: f64::NAN,
            end_sec: 1.0,
            pixel_width: 100,
        })
        .is_err());
        assert!(validate_query(&WaveformViewDto {
            start_sec: 1.0,
            end_sec: 1.0,
            pixel_width: 100,
        })
        .is_err());
        assert!(validate_query(&WaveformViewDto {
            start_sec: 0.0,
            end_sec: 1.0,
            pixel_width: MAX_QUERY_PIXEL_WIDTH + 1,
        })
        .is_err());
    }
}
