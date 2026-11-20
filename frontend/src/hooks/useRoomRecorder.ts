// 会议录制 Hook：客户端 canvas 合成录制
// 将「视频画面 + 标注画布 + 会议水印 + 实时时间戳」合成到一块离屏画布，
// 混入房间内所有音频轨后交给 MediaRecorder，停止时自动上传到后端。
import { useCallback, useEffect, useRef, useState } from 'react';
import { Track } from 'livekit-client';
import { useRoomContext } from '@livekit/components-react';
import * as meetingApi from '@/api/meeting';

/** 合成画布分辨率 */
const CANVAS_W = 1280;
const CANVAS_H = 720;
/** 录制帧率 */
const FPS = 25;
/** 单次分片时长（毫秒），保证长时间录制内存可控 */
const CHUNK_MS = 1000;

interface Options {
  /** 会议 ID，用于上传录制文件 */
  meetingID: string;
  /** 会议标题，作为水印内容 */
  meetingTitle: string;
  /** 当前用户名，作为水印内容 */
  userName: string;
  /** 获取主画面 video 元素（可能是摄像头或屏幕共享） */
  getVideoElement: () => HTMLVideoElement | null;
  /** 获取标注画布（静态标记 / 激光笔 / 白板） */
  getAnnotationCanvas: () => HTMLCanvasElement | null;
}

export interface RoomRecorderState {
  /** 是否正在录制 */
  recording: boolean;
  /** 正在上传录制文件 */
  saving: boolean;
  /** 已录制秒数 */
  elapsed: number;
  /** 最近一次错误信息 */
  error: string | null;
  /** 开始录制 */
  start: () => Promise<void>;
  /** 结束录制并上传 */
  stop: () => Promise<void>;
}

/** 把视频/画布等比居中绘制到目标画布（contain 模式） */
function drawContain(
  ctx: CanvasRenderingContext2D,
  source: HTMLVideoElement | HTMLCanvasElement,
  w: number,
  h: number,
) {
  const sw = source instanceof HTMLVideoElement ? source.videoWidth : source.width;
  const sh = source instanceof HTMLVideoElement ? source.videoHeight : source.height;
  if (!sw || !sh) return;

  const scale = Math.min(w / sw, h / sh);
  const dw = sw * scale;
  const dh = sh * scale;
  ctx.drawImage(source, (w - dw) / 2, (h - dh) / 2, dw, dh);
}

/** 秒数格式化为 HH:MM:SS */
function formatClock(totalSec: number): string {
  const s = Math.max(0, Math.floor(totalSec));
  const hh = String(Math.floor(s / 3600)).padStart(2, '0');
  const mm = String(Math.floor((s % 3600) / 60)).padStart(2, '0');
  const ss = String(s % 60).padStart(2, '0');
  return `${hh}:${mm}:${ss}`;
}

/** 当前时间格式化为 YYYY-MM-DD HH:mm:ss */
function formatNow(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

/**
 * 会议录制 Hook
 * - 画面：主视频 + 标注层（画线 / 激光笔 / 白板）实时合成
 * - 水印：会议标题 + 录制人 + 实时时间戳 + REC 标识
 * - 音频：混入本地麦克风与房间内所有远端音频
 * - 停止后自动上传后端并生成录制记录
 */
export function useRoomRecorder(opts: Options): RoomRecorderState {
  const room = useRoomContext();
  const [recording, setRecording] = useState(false);
  const [saving, setSaving] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [error, setError] = useState<string | null>(null);

  // 录制运行时资源（避免触发重渲染）
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const rafRef = useRef(0);
  const timerRef = useRef<number | null>(null);
  const audioCtxRef = useRef<AudioContext | null>(null);
  const startedAtRef = useRef(0);

  /** 绘制一帧合成画面：视频 → 标注 → 水印 → 时间戳 */
  const drawFrame = useCallback(() => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) return;

    // 背景
    ctx.fillStyle = '#0b1220';
    ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

    // 1. 主画面（摄像头或屏幕共享）
    const video = opts.getVideoElement();
    if (video && video.readyState >= 2) {
      try {
        drawContain(ctx, video, CANVAS_W, CANVAS_H);
      } catch {
        // 视频尚未产生可绘制帧，跳过本帧
      }
    }

    // 2. 标注层（白板会自带白底，因此无论视频是否存在都要叠加）
    const annotation = opts.getAnnotationCanvas();
    if (annotation && annotation.width > 0 && annotation.height > 0) {
      try {
        drawContain(ctx, annotation, CANVAS_W, CANVAS_H);
      } catch {
        // 忽略单帧绘制异常
      }
    }

    // 3. 会议水印（左下角：会议名称 + 录制人）
    const watermark = `${opts.meetingTitle || '在线会议'} · ${opts.userName || '参会者'}`;
    ctx.save();
    ctx.font = '600 22px "Microsoft YaHei", sans-serif';
    const textW = ctx.measureText(watermark).width;
    ctx.fillStyle = 'rgba(0,0,0,0.45)';
    ctx.fillRect(24, CANVAS_H - 72, textW + 32, 44);
    ctx.fillStyle = 'rgba(255,255,255,0.92)';
    ctx.textBaseline = 'middle';
    ctx.fillText(watermark, 40, CANVAS_H - 50);
    ctx.restore();

    // 4. 时间戳与录制时长（右上角）
    const elapsedSec = (Date.now() - startedAtRef.current) / 1000;
    const clock = `${formatNow()}  REC ${formatClock(elapsedSec)}`;
    ctx.save();
    ctx.font = '500 18px Consolas, "Microsoft YaHei", monospace';
    const clockW = ctx.measureText(clock).width;
    ctx.fillStyle = 'rgba(0,0,0,0.45)';
    ctx.fillRect(CANVAS_W - clockW - 56, 20, clockW + 32, 36);
    ctx.fillStyle = '#ffffff';
    ctx.textBaseline = 'middle';
    ctx.fillText(clock, CANVAS_W - clockW - 40, 38);

    // 左上角红色录制指示灯
    ctx.beginPath();
    ctx.fillStyle = '#ef4444';
    ctx.arc(40, 38, 8, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    rafRef.current = requestAnimationFrame(drawFrame);
  }, [opts]);

  /** 收集房间内所有音频轨（本地麦克风 + 远端参会者） */
  const buildAudioMix = useCallback(() => {
    const audioCtx = new AudioContext();
    audioCtxRef.current = audioCtx;
    const dest = audioCtx.createMediaStreamDestination();

    /** 把一条 MediaStreamTrack 接入混音目标 */
    const attach = (track?: MediaStreamTrack | null) => {
      if (!track || track.readyState === 'ended') return;
      try {
        const source = audioCtx.createMediaStreamSource(new MediaStream([track]));
        source.connect(dest);
      } catch {
        // 单条音频轨不可用时忽略
      }
    };

    // 本地麦克风
    attach(room.localParticipant.getTrackPublication(Track.Source.Microphone)?.audioTrack?.mediaStreamTrack);

    // 远端参会者音频
    room.remoteParticipants.forEach((participant) => {
      participant.audioTrackPublications.forEach((pub) => {
        attach(pub.track?.mediaStreamTrack);
      });
    });

    return dest.stream;
  }, [room]);

  /** 停止录制后上传文件并生成录制记录 */
  const upload = useCallback(async () => {
    const blob = new Blob(chunksRef.current, { type: 'video/webm' });
    chunksRef.current = [];
    const durationSec = Math.round((Date.now() - startedAtRef.current) / 1000);

    if (blob.size === 0) {
      setError('录制内容为空，未生成文件');
      return;
    }

    setSaving(true);
    try {
      const stamp = new Date().toISOString().replace(/[:.]/g, '-');
      await meetingApi.uploadRecording(opts.meetingID, blob, durationSec, `meeting-${stamp}.webm`);
    } catch (e) {
      setError((e as Error).message || '录制文件上传失败');
    } finally {
      setSaving(false);
      // 音轨已用完，释放混音上下文
      await audioCtxRef.current?.close().catch(() => undefined);
      audioCtxRef.current = null;
    }
  }, [opts.meetingID]);

  /** 开始录制 */
  const start = useCallback(async () => {
    if (recorderRef.current) return;
    setError(null);

    // 准备合成画布
    if (!canvasRef.current) {
      const canvas = document.createElement('canvas');
      canvas.width = CANVAS_W;
      canvas.height = CANVAS_H;
      canvasRef.current = canvas;
    }

    const canvas = canvasRef.current;
    const videoStream = canvas.captureStream(FPS);
    const audioTracks = buildAudioMix().getAudioTracks();
    const stream = new MediaStream([...videoStream.getVideoTracks(), ...audioTracks]);

    // 优先 VP9，回退 VP8 / 默认
    const mime = ['video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm']
      .find((t) => typeof MediaRecorder !== 'undefined' && MediaRecorder.isTypeSupported(t));

    let recorder: MediaRecorder;
    try {
      recorder = new MediaRecorder(stream, mime ? { mimeType: mime, videoBitsPerSecond: 2_500_000 } : undefined);
    } catch (e) {
      setError((e as Error).message || '当前浏览器不支持录制');
      audioCtxRef.current?.close().catch(() => undefined);
      audioCtxRef.current = null;
      return;
    }

    chunksRef.current = [];
    recorder.ondataavailable = (ev) => {
      if (ev.data && ev.data.size > 0) chunksRef.current.push(ev.data);
    };
    recorder.onstop = () => {
      stream.getTracks().forEach((t) => t.stop());
      void upload();
    };

    startedAtRef.current = Date.now();
    recorder.start(CHUNK_MS);
    recorderRef.current = recorder;
    setRecording(true);
    setElapsed(0);

    timerRef.current = window.setInterval(() => {
      setElapsed(Math.floor((Date.now() - startedAtRef.current) / 1000));
    }, 1000);

    rafRef.current = requestAnimationFrame(drawFrame);
  }, [buildAudioMix, drawFrame, upload]);

  /** 停止录制 */
  const stop = useCallback(async () => {
    const recorder = recorderRef.current;
    if (!recorder) return;

    if (timerRef.current !== null) {
      window.clearInterval(timerRef.current);
      timerRef.current = null;
    }
    cancelAnimationFrame(rafRef.current);

    if (recorder.state !== 'inactive') recorder.stop();
    recorderRef.current = null;
    setRecording(false);
    // 音轨在 onstop → upload 中统一释放
  }, []);

  // 组件卸载时释放资源
  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearInterval(timerRef.current);
      cancelAnimationFrame(rafRef.current);
      if (recorderRef.current && recorderRef.current.state !== 'inactive') {
        recorderRef.current.stop();
      }
      recorderRef.current = null;
      void audioCtxRef.current?.close().catch(() => undefined);
      audioCtxRef.current = null;
    };
  }, []);

  return { recording, saving, elapsed, error, start, stop };
}

export default useRoomRecorder;
