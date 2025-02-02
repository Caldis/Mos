import Cocoa

class DraggingImageView: NSImageView {
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.isEnabled = true
    }
    
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let image = self.image else { return }
        
        let bundleURL = Bundle.main.bundleURL as NSURL
        let draggingItem = NSDraggingItem(pasteboardWriter: bundleURL)
        
        let imageRect = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        draggingItem.setDraggingFrame(imageRect, contents: image)
        
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

extension DraggingImageView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
} 