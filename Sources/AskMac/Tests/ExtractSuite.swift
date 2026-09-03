//  Ask for Mac — MIT licensed. See LICENSE.
import Foundation
import AppKit
import PDFKit

enum ExtractSuite {
    static func write(_ name: String, _ s: String, in dir: URL) throws -> URL { let u = dir.appendingPathComponent(name); try s.write(to: u, atomically: true, encoding: .utf8); return u }
    static let suite = TestSuite(name: "Extract", cases: [
        TestCase(name: "plain, markdown, rtf, html, pdf, docx") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let a = try write("a.txt", "The deposit is $2,400.", in: dir), b = try write("b.md", "# Lease\n\nDeposit **$2,400**", in: dir), c = try write("c.html", "<html><body><p>Deposit is <b>$2,400</b></p></body></html>", in: dir)
            t.check(Extract.text(from: a)?.contains("$2,400") == true, "txt")
            t.check(Extract.text(from: b)?.contains("Deposit") == true, "md")
            t.check(Extract.text(from: c)?.contains("Deposit is $2,400") == true, "html stripped")
            let rtf = try NSAttributedString(string: "Rent is due on the first.").data(from: NSRange(location: 0, length: 25), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try rtf.write(to: dir.appendingPathComponent("d.rtf")); t.check(Extract.text(from: dir.appendingPathComponent("d.rtf"))?.contains("Rent is due") == true, "rtf")
            let docx = try NSAttributedString(string: "Word says the crown costs 1,150.").data(from: NSRange(location: 0, length: 32), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
            try docx.write(to: dir.appendingPathComponent("e.docx")); t.check(Extract.text(from: dir.appendingPathComponent("e.docx"))?.contains("crown costs 1,150") == true, "docx")
            // A PDF with real text: draw a page.
            let pdf = PDFDocument(); let page = PDFPage(); pdf.insert(page, at: 0)
            let data = NSMutableData(); let consumer = CGDataConsumer(data: data as CFMutableData)!; var box = CGRect(x: 0, y: 0, width: 400, height: 300)
            let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!; ctx.beginPDFPage(nil)
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false); NSGraphicsContext.current = ns
            NSAttributedString(string: "Dentist invoice: crown 1150 dollars, paid in March.", attributes: [.font: NSFont.systemFont(ofSize: 14)]).draw(at: NSPoint(x: 20, y: 200))
            NSGraphicsContext.current = nil; ctx.endPDFPage(); ctx.closePDF()
            try (data as Data).write(to: dir.appendingPathComponent("f.pdf"))
            t.check(Extract.text(from: dir.appendingPathComponent("f.pdf"))?.contains("crown 1150") == true, "pdf text: \(Extract.text(from: dir.appendingPathComponent("f.pdf")) ?? "nil")")
            let empty = try write("empty.txt", "   ", in: dir); t.check(Extract.text(from: empty) == nil, "empty is nil")
            try Data([0, 1, 2, 3, 255, 254]).write(to: dir.appendingPathComponent("g.bin")); t.check(Extract.text(from: dir.appendingPathComponent("g.bin")) == nil, "binary is nil")
        },
        TestCase(name: "emlx: headers, quoted-printable, multipart, encoded subject") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let msg = "From: Sam Rivera <sam@example.com>\r\nTo: you@example.com\r\nSubject: =?UTF-8?Q?Roof_estimate_=E2=80=94_revised?=\r\nDate: Tue, 1 Sep 2026 09:15:00 -0700\r\nContent-Type: multipart/alternative; boundary=\"XYZ\"\r\n\r\n--XYZ\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nThe roof estimate came to =244,800 with the gutters.\r\n--XYZ\r\nContent-Type: text/html\r\n\r\n<p>The roof estimate came to $4,800 with the gutters.</p>\r\n--XYZ--\r\n"
            let emlx = "\(msg.utf8.count)\n" + msg + "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>flags</key><integer>0</integer></dict></plist>\n"
            try emlx.write(to: dir.appendingPathComponent("1.emlx"), atomically: true, encoding: .utf8)
            let m = Extract.mail(from: dir.appendingPathComponent("1.emlx"))
            t.equal(m?.subject, "Roof estimate — revised", "subject decoded"); t.equal(m?.from, "Sam Rivera <sam@example.com>", "from")
            t.check(m?.body.contains("$4,800 with the gutters") == true, "quoted-printable body: \(m?.body ?? "nil")")
            t.check(m?.date != nil, "date parsed")
            let text = Extract.text(from: dir.appendingPathComponent("1.emlx")); t.check(text?.hasPrefix("Roof estimate") == true && text?.contains("From: Sam") == true, "text form includes headers")
        },
        TestCase(name: "screenshots are read with on-device text recognition") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let img = NSImage(size: NSSize(width: 600, height: 200)); img.lockFocus()
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 600, height: 200).fill()
            NSAttributedString(string: "WIFI PASSWORD: sunflower42", attributes: [.font: NSFont.systemFont(ofSize: 36, weight: .semibold), .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 30, y: 80))
            img.unlockFocus()
            let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try png.write(to: dir.appendingPathComponent("Screenshot 2026-09-01.png"))
            let text = Extract.text(from: dir.appendingPathComponent("Screenshot 2026-09-01.png"))
            t.check(text?.lowercased().contains("sunflower42") == true, "ocr text: \(text ?? "nil")")
        },
        TestCase(name: "html-only mail is stripped") { t in
            let m = Extract.parseRFC822("Subject: Hi\nContent-Type: text/html\n\n<html><body><p>Deposit <b>returned</b>.</p></body></html>")
            t.check(m.body.contains("Deposit returned"), "stripped: \(m.body)"); t.equal(m.subject, "Hi", "subject")
        },
    ])
}
