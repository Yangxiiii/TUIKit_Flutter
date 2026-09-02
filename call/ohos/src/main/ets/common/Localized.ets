// HarmonyOS resource keys disallow ".", so dotted keys like "TUICallKit.answer"
// are normalised to "TUICallKit_answer" before lookup.
//
// HarmonyOS 资源键不允许 "."，所以像 "TUICallKit.answer" 这样的点号键会在查找前被规范化为 "TUICallKit_answer"。

import { common } from '@kit.AbilityKit';
import resourceManager from '@ohos.resourceManager';
import { Logger } from './utils/Logger';

let appContext: common.UIAbilityContext | common.Context | null = null;

export function setLocalizedContext(context: common.UIAbilityContext | common.Context): void {
  appContext = context;
}

function normalizeKey(key: string): string {
  return key.replace(/\./g, '_');
}

/** Returns the localized string for `key`. Falls back to raw key on missing context. */

/* 返回 `key` 的本地化字符串。如果上下文缺失，则回退返回原始 key。 */
export function TUICallKitLocalize(key: string): string {
  const normalized = normalizeKey(key);
  if (!appContext) {
    return normalized;
  }
  try {
    const rm: resourceManager.ResourceManager = appContext.resourceManager;
    return rm.getStringByNameSync(normalized);
  } catch (e) {
    Logger.warn('TUICallKitLocalize miss key=', normalized, 'err=', e);
    return normalized;
  }
}

export function TUICallKitLocalizeResource(key: string): Resource {
  const normalized = normalizeKey(key);
  return $r('app.string.' + normalized);
}
