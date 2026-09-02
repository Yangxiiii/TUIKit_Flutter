@Component
export struct ControlsButton {
  @Prop image: Resource | undefined = undefined;
  @Prop title: string = '';

  /** Set to 0 with the parent's `.animation({ duration })` block to fade the title out smoothly. */

  /* 在父级的 `.animation({ duration })` 块中设置为 0，以便顺滑地淡出标题。 */
  @Prop titleAlpha: number = 1;
  @Prop titleTranslateY: number = 0;

  /** Whether button is selected (parent swaps to "_on" icon). */

  /* 按钮是否被选中（父级会切换到 “_on” 图标）。 */
  @Prop isSelected: boolean = false;

  @Prop isEnabled: boolean = true;

  @Prop imageSize: number = 60;

  /** Legacy prop — colour is baked into the PNG resource so this is ignored at render time. */

  /* 旧属性 — 颜色已嵌入 PNG 资源中，因此渲染时会被忽略。 */
  bgColor: string = '';

  onTap: () => void = (): void => { };

  build() {
    Column({ space: 10 }) {
      if (this.image !== undefined) {
        Image(this.image)
          .width(this.imageSize)
          .height(this.imageSize)
          .objectFit(ImageFit.Contain)
          .opacity(this.isEnabled ? 1.0 : 0.4)
          .onClick((): void => {
            if (this.isEnabled) {
              this.onTap();
            }
          });
      }

      Text(this.title)
        .width(100)
        .height(15)
        .fontColor('#FFFFFFFF')
        .fontSize(12)
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .opacity(this.titleAlpha)
        .translate({ x: 0, y: this.titleTranslateY });
    }
    .alignItems(HorizontalAlign.Center);
  }
}
