//
//  ZNSTextAttachmentLabel.swift
//
//
//  Created by https://zhgchg.li on 2023/3/5.
//

import UIKit
import MobileCoreServices

import UniformTypeIdentifiers

public class ZNSTextAttachmentCore: NSTextAttachment {

    public let imageURL: URL
    public weak var delegate: ZNSTextAttachmentDelegate?
    public weak var dataSource: ZNSTextAttachmentDataSource?
    
    private let origin: CGPoint?
    private let imageWidth: CGFloat?
    private let imageHeight: CGFloat?
    
    private var isLoading: Bool = false
    private var sources: [WeakZNSTextAttachmentable] = []
    private var urlSessionDataTask: URLSessionDataTask?
    
    public init(imageURL: URL, imageWidth: CGFloat? = nil, imageHeight: CGFloat? = nil, placeholderImage: UIImage? = nil, placeholderImageOrigin: CGPoint? = nil) {
        self.imageURL = imageURL
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.origin = placeholderImageOrigin
        
        if let placeholderImageData = placeholderImage?.pngData() {
            super.init(data: placeholderImageData, ofType: "public.png")
        } else {
            super.init(data: nil, ofType: nil)
        }
        
        self.image = placeholderImage
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func register(_ source: ZNSTextAttachmentable) {
        self.sources.append(WeakZNSTextAttachmentable(source))
    }
    
    public func startDownload() {
        guard !isLoading else { return }
        isLoading = true
        
        if let dataSource = self.dataSource {
            dataSource.zNSTextAttachment(self, loadImageURL: imageURL, completion: { data, mimeType  in
                self.dataDownloaded(data, mimeType: mimeType)
                self.isLoading = false
            })
        } else {
            
            if let regex = try? NSRegularExpression(pattern: #"^data:image/(jpeg|jpg|png);base64,\s*(([A-Za-z0-9+/]*={0,2})+)$"#),
                let firstMatch = regex.firstMatch(in: imageURL.absoluteString, options: [], range: NSRange(location: 0, length: imageURL.absoluteString.count)),
               firstMatch.range(at: 1).location != NSNotFound,
               firstMatch.range(at: 2).location != NSNotFound,
               let typeRange = Range(firstMatch.range(at: 1), in: imageURL.absoluteString),
               let base64StringRange = Range(firstMatch.range(at: 2), in: imageURL.absoluteString),
               let base64Data = Data(base64Encoded: String(imageURL.absoluteString[base64StringRange]), options: .ignoreUnknownCharacters) {
                
                let type = String(imageURL.absoluteString[typeRange])
                self.dataDownloaded(base64Data, mimeType: "image/"+type)
                
            } else {
                let urlSessionDataTask = URLSession.shared.dataTask(with: imageURL) { (data, response, error) in
                    guard let data = data, error == nil else {
                        print(error?.localizedDescription as Any)
                        return
                    }
                    
                    
                    self.dataDownloaded(data, mimeType: response?.mimeType)
                    self.isLoading = false
                    self.urlSessionDataTask = nil
                }
                self.urlSessionDataTask = urlSessionDataTask
                urlSessionDataTask.resume()
            }
        }
    }
    
    public override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        
        if let image = self.image {
            return CGRect(origin: origin ?? .zero, size: image.size)
        }
        
        return .zero
    }
    
    public func dataDownloaded(_ data: Data, mimeType: String?) {
        let fileType: String
        let pathExtension = self.imageURL.pathExtension
        if #available(iOS 14.0, *) {
            if let mimeType = mimeType, let utType = UTType(mimeType: mimeType) {
                fileType = utType.identifier
            } else if let utType = UTType(filenameExtension: pathExtension) {
                fileType = utType.identifier
            } else {
                fileType = "public.\(pathExtension)"
            }
        } else {
            if let mimeType = mimeType, let utTypeIdentifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType as CFString, nil)?.takeRetainedValue() as? String {
                fileType = utTypeIdentifier
            } else if let utTypeIdentifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension as CFString, nil)?.takeRetainedValue() as? String {
                fileType = utTypeIdentifier
            } else {
                fileType = "public.\(pathExtension)"
            }
        }
        let image = UIImage(data: data)
        DispatchQueue.main.async {
            let loaded = ZResizableNSTextAttachment(imageSize: image?.size, fixedWidth: self.imageWidth, fixedHeight: self.imageHeight, data: data, type: fileType)
            self.sources.forEach { source in
                source.value?.replace(attachment: self, to: loaded)
            }
            self.delegate?.zNSTextAttachment(didLoad: self, to: loaded)
        }
    }
}

public extension ZNSTextAttachmentCore {
    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {

        if let textStorage = textContainer?.layoutManager?.textStorage {
            register(textStorage)
        }
        
        startDownload()
        
        if let image = self.image {
            return image
        }
        
        return nil
    }
}
