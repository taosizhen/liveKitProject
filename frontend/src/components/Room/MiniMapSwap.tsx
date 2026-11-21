// 圆桌 ⇄ 参会列表 小地图互换容器
// - roundTableMain=false：视频舞台全屏，圆桌为左下小地图
// - roundTableMain=true：圆桌全屏，参会列表为左下小地图
// 舞台与圆桌始终挂载（圆桌全屏时舞台仅隐藏），避免 VideoTrack 重挂载黑屏闪烁
import type { ReactNode } from 'react';

interface MiniMapSwapProps {
  /** true=圆桌全屏/列表小地图；false=舞台全屏/圆桌小地图 */
  roundTableMain: boolean;
  /** 点击小地图互换 */
  onSwap: () => void;
  /** 圆桌视图渲染函数（按当前位置传 size，保证组件位置稳定不重挂载） */
  renderRoundTable: (size: 'full' | 'mini') => ReactNode;
  /** 成员列表小地图内容（compact 形态） */
  memberListMini: ReactNode;
  /** 默认舞台内容（视频会议画面，圆桌全屏时保持挂载但隐藏） */
  stage: ReactNode;
  /** 标注中隐藏小地图浮层，避免遮挡画布 */
  hideOverlays?: boolean;
}

/** 圆桌/列表小地图互换容器 */
export default function MiniMapSwap({
  roundTableMain,
  onSwap,
  renderRoundTable,
  memberListMini,
  stage,
  hideOverlays = false,
}: MiniMapSwapProps) {
  // 标注中强制退回舞台主画面：圆桌与标注互斥，退出标注后自动恢复圆桌全屏
  const showRoundTable = roundTableMain && !hideOverlays;

  return (
    <div className="absolute inset-0">
      {/* 舞台始终挂载，圆桌全屏时仅视觉隐藏（标注中即使 roundTableMain=true 也要显示舞台） */}
      <div className={`absolute inset-0 ${showRoundTable ? 'invisible' : ''}`}>{stage}</div>

      {/* 圆桌：全屏 ⇄ 小地图，仅改容器类名与 size prop，组件位置稳定 */}
      <div
        onClick={showRoundTable || hideOverlays ? undefined : onSwap}
        title={showRoundTable || hideOverlays ? undefined : '点击展开同框圆桌'}
        className={
          showRoundTable
            ? 'absolute inset-0'
            : `absolute left-3 bottom-3 z-20 ${hideOverlays ? 'hidden' : ''}`
        }
      >
        {renderRoundTable(showRoundTable ? 'full' : 'mini')}
      </div>

      {/* 成员列表小地图（仅圆桌全屏且非标注时显示，点击切回舞台） */}
      {showRoundTable && (
        <div
          onClick={onSwap}
          title="点击切回主舞台"
          className="absolute left-3 bottom-3 z-20 w-56 max-h-64 overflow-y-auto rounded-xl border border-white/20 bg-slate-900/95 shadow-xl cursor-pointer hover:border-brand-400 transition"
        >
          {memberListMini}
        </div>
      )}
    </div>
  );
}
