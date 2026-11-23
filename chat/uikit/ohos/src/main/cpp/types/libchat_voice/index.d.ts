/** 按顺序合并音轨，或按毫秒上限裁剪单条音轨；输出新文件并返回音频的毫秒时长。 */
export const mergeRecordings: (paths: string[], destination: string, maxDurationMs?: number) => Promise<number>;
