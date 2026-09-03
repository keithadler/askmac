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
            // Two pages: passages carry their page number.
            let two = PDFDocument(); two.insert(PDFPage(), at: 0); two.insert(PDFPage(), at: 1)
            let d2 = NSMutableData(); let con2 = CGDataConsumer(data: d2 as CFMutableData)!; var box2 = CGRect(x: 0, y: 0, width: 400, height: 300)
            let c2 = CGContext(consumer: con2, mediaBox: &box2, nil)!
            for (i, line) in ["Page one talks about the lease.", "Page two says the deposit is 2400."].enumerated() {
                c2.beginPDFPage(nil); NSGraphicsContext.current = NSGraphicsContext(cgContext: c2, flipped: false)
                NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 14)]).draw(at: NSPoint(x: 20, y: 200)); NSGraphicsContext.current = nil; c2.endPDFPage(); _ = i
            }
            c2.closePDF(); try (d2 as Data).write(to: dir.appendingPathComponent("two.pdf"))
            let pages = Extract.pdfPages(dir.appendingPathComponent("two.pdf")); t.equal(pages?.count, 2, "two pages")
            let ps = Passages.split(pages: pages ?? [], source: Candidate(url: dir.appendingPathComponent("two.pdf"), kind: .pdf, modified: nil))
            t.equal(ps.map { $0.page }, [1, 2], "page numbers on passages")
            t.check(ps.last?.text.contains("2400") == true, "second page text")
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
        TestCase(name: "xlsx and pptx: text out of the zip") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            // Minimal office zips built with the system zip tool.
            let x = dir.appendingPathComponent("x"); try FileManager.default.createDirectory(at: x.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)
            try "<sst><si><t>Budget</t></si><si><t>Roof repair 4,800</t></si></sst>".write(to: x.appendingPathComponent("xl/sharedStrings.xml"), atomically: true, encoding: .utf8)
            try "<worksheet><sheetData><row><c><v>1</v></c></row></sheetData></worksheet>".write(to: x.appendingPathComponent("xl/worksheets/sheet1.xml"), atomically: true, encoding: .utf8)
            let pp = dir.appendingPathComponent("p"); try FileManager.default.createDirectory(at: pp.appendingPathComponent("ppt/slides"), withIntermediateDirectories: true)
            try "<p:sld><p:sp><a:p><a:r><a:t>Quarterly review</a:t></a:r></a:p><a:p><a:r><a:t>Revenue up 12%</a:t></a:r></a:p></p:sp></p:sld>".write(to: pp.appendingPathComponent("ppt/slides/slide1.xml"), atomically: true, encoding: .utf8)
            for (src, name) in [(x, "budget.xlsx"), (pp, "review.pptx")] {
                let z = Process(); z.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); z.currentDirectoryURL = src; z.arguments = ["-qr", dir.appendingPathComponent(name).path, "."]; try z.run(); z.waitUntilExit()
            }
            t.check(Extract.text(from: dir.appendingPathComponent("budget.xlsx"))?.contains("Roof repair 4,800") == true, "xlsx: \(Extract.text(from: dir.appendingPathComponent("budget.xlsx")) ?? "nil")")
            let p = Extract.text(from: dir.appendingPathComponent("review.pptx")); t.check(p?.contains("Quarterly review") == true && p?.contains("Revenue up 12%") == true, "pptx: \(p ?? "nil")")
            t.check(p?.contains("<") == false, "no tags left")
        },
        TestCase(name: "iWork documents through their preview image") { t in
            let dir = TestKit.tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
            let img = NSImage(size: NSSize(width: 600, height: 200)); img.lockFocus()
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 600, height: 200).fill()
            NSAttributedString(string: "Quarterly budget: total 84,000", attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.black]).draw(at: NSPoint(x: 30, y: 80))
            img.unlockFocus()
            let jpg = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
            // Package form (a folder) and zip form, both with preview.jpg at the top.
            let pkg = dir.appendingPathComponent("Budget.numbers"); try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true); try jpg.write(to: pkg.appendingPathComponent("preview.jpg"))
            t.check(Extract.text(from: pkg)?.contains("84,000") == true, "package preview read: \(Extract.text(from: pkg) ?? "nil")")
            let src = dir.appendingPathComponent("src"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true); try jpg.write(to: src.appendingPathComponent("preview.jpg"))
            let z = Process(); z.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); z.currentDirectoryURL = src; z.arguments = ["-qr", dir.appendingPathComponent("Plan.pages").path, "."]; try z.run(); z.waitUntilExit()
            t.check(Extract.text(from: dir.appendingPathComponent("Plan.pages"))?.contains("84,000") == true, "zip preview read")
            let none = dir.appendingPathComponent("Empty.key"); try FileManager.default.createDirectory(at: none, withIntermediateDirectories: true)
            t.check(Extract.text(from: none) == nil, "no preview is nil, not a crash")
        },
        TestCase(name: "html-only mail is stripped") { t in
            let m = Extract.parseRFC822("Subject: Hi\nContent-Type: text/html\n\n<html><body><p>Deposit <b>returned</b>.</p></body></html>")
            t.check(m.body.contains("Deposit returned"), "stripped: \(m.body)"); t.equal(m.subject, "Hi", "subject")
        },
    ])
}
