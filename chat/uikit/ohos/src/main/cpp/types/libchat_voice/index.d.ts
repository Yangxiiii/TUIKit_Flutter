/** 将录音音轨按顺序合并到新文件，异步返回完整音频的毫秒时长。 */
export const mergeRecordings: (paths: string[], destination: string) => Promise<number>;
