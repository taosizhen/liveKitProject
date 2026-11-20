// 会议标注层：静态标记（画笔/矩形/圆/箭头/文字）+ 动态激光笔 + 白板
// 基于 LiveKit Data Channel 在房间内实时同步，标注画布同时供录制合成使用
import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import {
  ArrowUpRight, Circle, Pencil, Presentation, Square, Trash2, Type, X, Zap,
} from 'lucide-react';
import { RoomEvent } from 'livekit-client';
import { useRoomContext } from '@livekit/components-react';

/** 标注工具 */
export type AnnotationTool = 'pen' | 'rect' | 'circle' | 'arrow' | 'text' | 'laser';

/** 归一化坐标 [x, y]，取值 0~1，保证不同分辨率下同步一致 */
type Point = [number, number];

/** 静态笔迹（持久保留，直到清空） */
interface Stroke {
  tool: Exclude<AnnotationTool, 'laser'>;
  color: string;
  width: number;
  points: Point[];
  text?: string;
}

/** 激光笔轨迹点（1.5s 后自动消失） */
interface LaserDot {
  /** 归一化坐标 */
  p: Point;
  /** 产生时间（performance.now） */
  at: number;
}

/** Data Channel 消息 */
type AnnotationMessage =
  | { src: 'annotation'; k: 'stroke'; s: Stroke }
  | { src: 'annotation'; k: 'clear' }
  | { src: 'annotation'; k: 'whiteboard'; on: boolean }
  | { src: 'annotation'; k: 'laser'; pts: LaserDot[] };

/** 对外暴露的方法：录制时读取标注画布 */
export interface AnnotationLayerHandle {
  getCanvas: () => HTMLCanvasElement | null;
  isWhiteboard: () => boolean;
}

interface Props {
  /** 是否处于标注模式（关闭时画布不拦截鼠标） */
  enabled: boolean;
  /** 退出标注模式 */
  onExit: () => void;
}

const COLORS = ['#ef4444', '#f59e0b', '#22c55e', '#3b82f6', '#a855f7', '#ffffff'];
const DATA_TOPIC = 'annotation';
const LASER_TTL = 1500;

/** 归一化坐标转像素坐标 */
function toPx(p: Point, w: number, h: number): [number, number] {
  return [p[0] * w, p[1] * h];
}

/** 在画布上绘制一条静态笔迹 */
function paintStroke(ctx: CanvasRenderingContext2D, s: Stroke, w: number, h: number) {
  ctx.save();
  ctx.strokeStyle = s.color;
  ctx.fillStyle = s.color;
  ctx.lineWidth = s.width;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';

  const first = s.points[0];
  const last = s.points[s.points.length - 1];

  if (s.tool === 'pen') {
    ctx.beginPath();
    s.points.forEach((pt, i) => {
      const [x, y] = toPx(pt, w, h);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  } else if (s.tool === 'rect') {
    const [x1, y1] = toPx(first, w, h);
    const [x2, y2] = toPx(last, w, h);
    ctx.strokeRect(Math.min(x1, x2), Math.min(y1, y2), Math.abs(x2 - x1), Math.abs(y2 - y1));
  } else if (s.tool === 'circle') {
    const [x1, y1] = toPx(first, w, h);
    const [x2, y2] = toPx(last, w, h);
    ctx.beginPath();
    ctx.ellipse(
      (x1 + x2) / 2, (y1 + y2) / 2,
      Math.abs(x2 - x1) / 2, Math.abs(y2 - y1) / 2,
      0, 0, Math.PI * 2,
    );
    ctx.stroke();
  } else if (s.tool === 'arrow') {
    const [x1, y1] = toPx(first, w, h);
    const [x2, y2] = toPx(last, w, h);
    const angle = Math.atan2(y2 - y1, x2 - x1);
    const head = 16;
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(x2, y2);
    ctx.lineTo(x2 - head * Math.cos(angle - Math.PI / 6), y2 - head * Math.sin(angle - Math.PI / 6));
    ctx.lineTo(x2 - head * Math.cos(angle + Math.PI / 6), y2 - head * Math.sin(angle + Math.PI / 6));
    ctx.closePath();
    ctx.fill();
  } else if (s.tool === 'text') {
    const [x, y] = toPx(first, w, h);
    ctx.font = `600 ${s.width * 5}px "Microsoft YaHei", sans-serif`;
    ctx.textBaseline = 'top';
    ctx.fillText(s.text ?? '', x, y);
  }
  ctx.restore();
}

const AnnotationLayer = forwardRef<AnnotationLayerHandle, Props>(function AnnotationLayer(
  { enabled, onExit },
  ref,
) {
  const room = useRoomContext();
  const wrapRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const cacheRef = useRef<HTMLCanvasElement | null>(null);
  const strokesRef = useRef<Stroke[]>([]);
  const laserRef = useRef<LaserDot[]>([]);
  const whiteboardRef = useRef(false);
  const draftingRef = useRef<{ tool: AnnotationTool; start: Point; current: Point; points: Point[] } | null>(null);
  const lastLaserSentRef = useRef(0);

  const [tool, setTool] = useState<AnnotationTool>('pen');
  const [color, setColor] = useState(COLORS[0]);
  const [whiteboard, setWhiteboard] = useState(false);

  /** 重绘静态标记缓存画布 */
  const redrawCache = useCallback(() => {
    const cache = cacheRef.current;
    if (!cache) return;
    const ctx = cache.getContext('2d');
    if (!ctx) return;
    const dpr = window.devicePixelRatio || 1;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, cache.width, cache.height);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    strokesRef.current.forEach((s) => paintStroke(ctx, s, cache.width / dpr, cache.height / dpr));
  }, []);

  /** 按容器尺寸与 DPR 同步画布 */
  const syncSize = useCallback(() => {
    const wrap = wrapRef.current;
    const canvas = canvasRef.current;
    if (!wrap || !canvas) return;

    const dpr = window.devicePixelRatio || 1;
    const w = wrap.clientWidth;
    const h = wrap.clientHeight;
    const nw = Math.max(1, Math.round(w * dpr));
    const nh = Math.max(1, Math.round(h * dpr));
    if (canvas.width === nw && canvas.height === nh && cacheRef.current) return;

    canvas.width = nw;
    canvas.height = nh;
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;

    // 重建静态缓存画布（尺寸变化后按新尺寸重绘历史笔迹）
    const cache = document.createElement('canvas');
    cache.width = nw;
    cache.height = nh;
    cacheRef.current = cache;
    redrawCache();
  }, [redrawCache]);

  // 尺寸监听
  useEffect(() => {
    const wrap = wrapRef.current;
    if (!wrap) return;
    const ro = new ResizeObserver(() => syncSize());
    ro.observe(wrap);
    syncSize();
    return () => ro.disconnect();
  }, [syncSize]);

  /** 广播标注消息给房间内其他参会者 */
  const post = useCallback((msg: AnnotationMessage) => {
    try {
      room.localParticipant.publishData(new TextEncoder().encode(JSON.stringify(msg)), {
        reliable: true,
        topic: DATA_TOPIC,
      });
    } catch {
      // 数据通道不可用时忽略
    }
  }, [room]);

  // 接收远端标注
  useEffect(() => {
    const onData = (payload: Uint8Array, _participant?: unknown, _kind?: unknown, topic?: string) => {
      if (topic !== DATA_TOPIC) return;
      try {
        const msg = JSON.parse(new TextDecoder().decode(payload)) as AnnotationMessage;
        if (msg.src !== 'annotation') return;
        if (msg.k === 'stroke') {
          strokesRef.current.push(msg.s);
          redrawCache();
        } else if (msg.k === 'clear') {
          strokesRef.current = [];
          redrawCache();
        } else if (msg.k === 'whiteboard') {
          whiteboardRef.current = msg.on;
          setWhiteboard(msg.on);
        } else if (msg.k === 'laser') {
          // 用接收端本地时钟重新打点：Flutter 端无法提供与 Web 相同基准的
          // performance.now()，若直接沿用对端 at 值会导致轨迹立即过期或永不淡出
          const now = performance.now();
          laserRef.current.push(...msg.pts.map((item) => ({ p: item.p, at: now })));
        }
      } catch {
        // 非标注消息，忽略
      }
    };
    room.on(RoomEvent.DataReceived, onData);
    return () => {
      room.off(RoomEvent.DataReceived, onData);
    };
  }, [room, redrawCache]);

  // 渲染循环：白板底色 + 静态标记 + 激光笔淡出 + 拖拽预览
  useEffect(() => {
    let rafId = 0;
    const loop = () => {
      const canvas = canvasRef.current;
      const ctx = canvas?.getContext('2d');
      if (canvas && ctx) {
        const dpr = window.devicePixelRatio || 1;
        const w = canvas.width / dpr;
        const h = canvas.height / dpr;

        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

        // 白板模式：铺白底遮住视频
        if (whiteboardRef.current) {
          ctx.fillStyle = '#ffffff';
          ctx.fillRect(0, 0, w, h);
        }

        // 静态标记
        if (cacheRef.current) {
          ctx.setTransform(1, 0, 0, 1, 0, 0);
          ctx.drawImage(cacheRef.current, 0, 0);
          ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        }

        // 动态激光笔：按存活时间淡出
        const now = performance.now();
        laserRef.current = laserRef.current.filter((p) => now - p.at < LASER_TTL);
        laserRef.current.forEach((p) => {
          const alpha = Math.max(0, 1 - (now - p.at) / LASER_TTL);
          const [x, y] = toPx(p.p, w, h);
          ctx.beginPath();
          ctx.fillStyle = `rgba(239,68,68,${alpha})`;
          ctx.arc(x, y, 8, 0, Math.PI * 2);
          ctx.fill();
        });

        // 正在拖拽绘制的预览
        const d = draftingRef.current;
        if (d && d.tool !== 'laser') {
          const preview: Stroke = {
            tool: d.tool as Stroke['tool'],
            color,
            width: 3,
            points: d.tool === 'pen' ? d.points : [d.start, d.current],
          };
          paintStroke(ctx, preview, w, h);
        }
      }
      rafId = requestAnimationFrame(loop);
    };
    rafId = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(rafId);
  }, [color]);

  useImperativeHandle(ref, () => ({
    getCanvas: () => canvasRef.current,
    isWhiteboard: () => whiteboardRef.current,
  }), []);

  /** 指针坐标转归一化坐标 */
  const getPoint = (e: React.PointerEvent<HTMLCanvasElement>): Point => {
    const rect = e.currentTarget.getBoundingClientRect();
    return [
      Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width)),
      Math.min(1, Math.max(0, (e.clientY - rect.top) / rect.height)),
    ];
  };

  const onPointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!enabled) return;
    e.currentTarget.setPointerCapture(e.pointerId);
    const p = getPoint(e);
    draftingRef.current = { tool, start: p, current: p, points: [p] };
    if (tool === 'laser') {
      laserRef.current.push({ p, at: performance.now() });
    }
  };

  const onPointerMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!enabled) return;
    const d = draftingRef.current;
    if (!d) return;
    const p = getPoint(e);
    d.current = p;

    if (d.tool === 'pen') {
      d.points.push(p);
    } else if (d.tool === 'laser') {
      laserRef.current.push({ p, at: performance.now() });
      // 节流广播激光轨迹
      const now = performance.now();
      if (now - lastLaserSentRef.current > 60) {
        lastLaserSentRef.current = now;
        post({ src: 'annotation', k: 'laser', pts: laserRef.current.slice(-6) });
      }
    }
  };

  const onPointerUp = () => {
    const d = draftingRef.current;
    draftingRef.current = null;
    if (!d || !enabled) return;
    if (d.tool === 'laser') return; // 激光笔临时轨迹，不落库

    let stroke: Stroke;
    if (d.tool === 'text') {
      const text = window.prompt('请输入标注文字');
      if (!text) return;
      stroke = { tool: 'text', color, width: 3, points: [d.start], text };
    } else {
      stroke = {
        tool: d.tool as Stroke['tool'],
        color,
        width: 3,
        points: d.tool === 'pen' ? d.points : [d.start, d.current],
      };
    }
    strokesRef.current.push(stroke);
    redrawCache();
    post({ src: 'annotation', k: 'stroke', s: stroke });
  };

  /** 清空所有标注 */
  const clearAll = () => {
    strokesRef.current = [];
    laserRef.current = [];
    redrawCache();
    post({ src: 'annotation', k: 'clear' });
  };

  /** 切换白板 */
  const toggleWhiteboard = () => {
    const next = !whiteboardRef.current;
    whiteboardRef.current = next;
    setWhiteboard(next);
    post({ src: 'annotation', k: 'whiteboard', on: next });
  };

  const toolBtn = (t: AnnotationTool, Icon: typeof Pencil, label: string) => (
    <button
      key={t}
      title={label}
      onClick={() => setTool(t)}
      className={`p-2 rounded-lg transition ${tool === t ? 'bg-brand-600 text-white' : 'text-white/80 hover:bg-white/10'}`}
    >
      <Icon className="w-4 h-4" />
    </button>
  );

  return (
    <div
      ref={wrapRef}
      className="absolute inset-0 z-20"
      style={{ pointerEvents: enabled ? 'auto' : 'none' }}
    >
      <canvas
        ref={canvasRef}
        className="block w-full h-full touch-none"
        style={{ cursor: enabled ? 'crosshair' : 'default' }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerLeave={onPointerUp}
      />

      {enabled && (
        <div className="absolute top-3 left-3 flex items-center gap-1 px-2 py-1.5 rounded-xl bg-slate-900/90 backdrop-blur border border-white/10">
          {toolBtn('pen', Pencil, '自由画笔')}
          {toolBtn('rect', Square, '矩形')}
          {toolBtn('circle', Circle, '圆形')}
          {toolBtn('arrow', ArrowUpRight, '箭头')}
          {toolBtn('text', Type, '文字')}
          {toolBtn('laser', Zap, '激光笔（动态）')}

          <span className="w-px h-6 bg-white/15 mx-1" />

          {COLORS.map((c) => (
            <button
              key={c}
              title={`颜色 ${c}`}
              onClick={() => setColor(c)}
              className={`w-5 h-5 rounded-full border ${color === c ? 'ring-2 ring-white' : 'border-white/30'}`}
              style={{ backgroundColor: c }}
            />
          ))}

          <span className="w-px h-6 bg-white/15 mx-1" />

          <button
            title="白板"
            onClick={toggleWhiteboard}
            className={`p-2 rounded-lg transition ${whiteboard ? 'bg-white text-slate-900' : 'text-white/80 hover:bg-white/10'}`}
          >
            <Presentation className="w-4 h-4" />
          </button>
          <button title="清空标注" onClick={clearAll} className="p-2 rounded-lg text-white/80 hover:bg-white/10">
            <Trash2 className="w-4 h-4" />
          </button>
          <button title="退出标注" onClick={onExit} className="p-2 rounded-lg text-white/80 hover:bg-white/10">
            <X className="w-4 h-4" />
          </button>
        </div>
      )}
    </div>
  );
});

export default AnnotationLayer;
