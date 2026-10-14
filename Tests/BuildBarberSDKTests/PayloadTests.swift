import Testing
import Foundation
@testable import BuildBarberSDK

@Suite struct PayloadTests {
    @Test func multipartContainsPartsAndTerminator() {
        var form = MultipartFormData(boundary: "B")
        form.addField(name: "metadata", value: Data("{}".utf8), mimeType: "application/json")
        form.addField(name: "video", value: Data([1, 2]), filename: "a.mp4", mimeType: "video/mp4")
        let text = String(decoding: form.finalized(), as: UTF8.self)
        #expect(text.contains("name=\"metadata\""))
        #expect(text.contains("filename=\"a.mp4\""))
        #expect(text.hasSuffix("--B--\r\n"))
        #expect(form.contentType == "multipart/form-data; boundary=B")
    }
}
