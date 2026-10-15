import { PdfView, pdfViewManager } from '@kit.PDFKit';
import { PdfPreviewParams } from '../model/PreviewParams';

// Routed only after checking both capability and the actual runtime exports.
@Entry
@Component
struct PdfPreview {
  @State errorMessage: string = '';
  @State ready: boolean = false;
  private controller: pdfViewManager.PdfController | undefined = undefined;
  aboutToAppear(): void { this.load(); }
  private async load(): Promise<void> {
    try {
      const params = this.getUIContext().getRouter().getParams() as PdfPreviewParams;
      if (!params || !params.path) throw new Error('缺少 PDF 文件路径');
      this.controller = new pdfViewManager.PdfController();
      await this.controller.loadDocument(params.path);
      this.ready = true;
    } catch (error) {
      this.errorMessage = `PDF 无法预览：${(error as Error).message || JSON.stringify(error)}`;
    }
  }
  build() {
    Column({ space: 16 }) {
      Row() { Text('PDF 预览').fontSize(22).layoutWeight(1); Button('返回资料台').onClick(() => this.getUIContext().getRouter().back()) }.width('100%')
      if (this.errorMessage) { Text(this.errorMessage).fontColor('#C55454') }
      else if (this.ready && this.controller) { PdfView({ controller: this.controller }).width('100%').layoutWeight(1) }
      else { LoadingProgress().width(40).height(40) }
    }.padding(24).width('100%').height('100%').backgroundColor($r('app.color.hub_canvas'))
  }
}
