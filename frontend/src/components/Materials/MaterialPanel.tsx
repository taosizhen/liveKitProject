// MaterialPanel：会议材料上传/列表/删除
import { useRef, useState } from 'react';
import { FileUp, FileText, Trash2, Download, XCircle } from 'lucide-react';

interface Props {
  meetingID: string;
  materials: Array<{ id: string; file_name: string; file_url: string; file_type: string; file_size: number; uploader_id?: string }>;
  onUpload: (file: File) => Promise<void>;
  onDelete: (id: string) => Promise<void>;
  className?: string;
}

/** 会议材料面板：拖拽上传 + 列表 + 删除 */
export default function MaterialPanel({ meetingID, materials, onUpload, onDelete, className }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);
  const [busy, setBusy] = useState(false);

  const handleFile = async (file?: File) => {
    if (!file) return;
    setBusy(true);
    try { await onUpload(file); } catch {}
    finally { setBusy(false); }
  };

  return (
    <div className={`bg-white rounded-lg border border-slate-200 ${className ?? ''}`}>
      <div className="px-4 py-3 border-b border-slate-100 flex items-center gap-2">
        <FileUp className="w-4 h-4 text-brand-600" />
        <span className="text-sm font-medium text-slate-700">会议材料</span>
        <span className="text-xs text-slate-400 ml-2">({materials.length})</span>
      </div>

      {/* 上传区（拖拽+点击） */}
      <div
        className={`m-3 border-2 border-dashed rounded-lg px-4 py-6 text-center text-sm cursor-pointer transition
          ${dragging ? 'border-brand-500 bg-brand-50/60' : 'border-slate-200 hover:border-brand-400 hover:bg-slate-50'}
          ${busy ? 'opacity-60 cursor-not-allowed' : ''}`}
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          e.preventDefault(); setDragging(false);
          handleFile(e.dataTransfer.files?.[0]);
        }}
        onClick={() => !busy && inputRef.current?.click()}
      >
        {busy ? (
          <div className="text-slate-500">上传中...</div>
        ) : (
          <>
            <FileUp className="w-6 h-6 mx-auto mb-2 text-slate-400" />
            <div className="text-slate-600">点击或拖拽文件到此上传</div>
            <div className="text-xs text-slate-400 mt-1">PDF / Word / Excel / 图片 / 视频 / 压缩包</div>
          </>
        )}
        <input ref={inputRef} type="file" className="hidden"
          onChange={(e) => handleFile(e.target.files?.[0])} />
      </div>

      {/* 列表 */}
      <div className="max-h-80 overflow-y-auto px-2 pb-2">
        {materials.length === 0 && (
          <div className="text-center text-slate-400 text-sm py-6">暂无材料</div>
        )}
        {materials.map((m) => (
          <div key={m.id} className="group flex items-center gap-3 px-2 py-2 rounded hover:bg-slate-50">
            <FileText className="w-5 h-5 text-brand-500 flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <div className="text-sm text-slate-700 truncate" title={m.file_name}>{m.file_name}</div>
              <div className="text-xs text-slate-400">
                {(m.file_size / 1024).toFixed(1)} KB · {m.file_type?.toUpperCase() || 'FILE'}
              </div>
            </div>
            <a href={m.file_url} target="_blank" rel="noreferrer"
              className="p-1.5 rounded hover:bg-slate-200 text-slate-500">
              <Download className="w-4 h-4" />
            </a>
            <button
              onClick={() => onDelete(m.id)}
              className="p-1.5 rounded hover:bg-red-50 text-slate-400 hover:text-red-500"
              title="删除"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          </div>
        ))}
      </div>
      {!meetingID && (
        <div className="px-3 pb-2 text-xs text-slate-400 flex items-center gap-1">
          <XCircle className="w-3 h-3" /> 尚未进入具体会议
        </div>
      )}
    </div>
  );
}
