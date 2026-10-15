// Capability declarations alone are insufficient on emulators: confirm the
// actual exports through a catchable dynamic import before routing to PDFKit.
export async function hasPdfPreview(): Promise<boolean> {
  if (!canIUse('SystemCapability.OfficeService.PDFService.Core')) return false;
  try {
    const api = await import('@hms.officeservice.PdfView');
    return typeof api.pdfViewManager.PdfController === 'function' && api.PdfView !== undefined;
  } catch (_) { return false; }
}
