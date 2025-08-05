import Cocoa
import HotKey

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem?
    var timer: Timer?
    var lastClipboardContents: String?
    var gptResponse: String?
    let openAIKey = ""
    
    
    let costExam: [[String: String]] = [
            [
              "question": "Reserve Analysis as a verb, is used in all of these areas except for:",
              "answer": "Control Costs."
            ],
            [
              "question": "We have a project to assemble 31 outdoor vinyl shed kits for a recreational resort. The kits are already bought and paid for by the owner, and a contractor is going to assemble them. The contract price for assembly is $3450. The owner knows you studied project management, and the project is underway, so they asked you to perform some EVM analysis forthem. • What is our EV, if by the status date our AC is $4300, we had planned on taking 6.0 hours to assemble each kit, and we assembled 18.5 kits?",
              "answer": "2058.87"
            ]
        ]
    
    var hotKey: HotKey? {
        didSet {
            guard let hotKey = hotKey else {
                return
            }

            hotKey.keyDownHandler = { [weak self] in
                self?.showContextMenu()
            }
        }
    }
    
    
    var examHotKey: HotKey? {
            didSet {
                guard let examHotKey = examHotKey else {
                    return
                }

                examHotKey.keyDownHandler = { [weak self] in
                    self?.showExamContextMenu()
                }
            }
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
            hotKey = HotKey(key: .e, modifiers: [.command])
            examHotKey = HotKey(key: .r, modifiers: [.command])

            timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(checkForClipboardChanges), userInfo: nil, repeats: true)
            window = TooltipWindow(contentRect: NSMakeRect(0, 0, 1, 1), styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = NSColor.clear
            window.isOpaque = false
            window.level = .floating
            window.ignoresMouseEvents = true
           
           statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
           if let button = statusItem?.button {
               button.image = NSImage(named: NSImage.Name("MKill"))
               button.image?.isTemplate = true  // Makes the icon adapt to light/dark theme.
           }
           constructMenu()
    }


    func applicationWillTerminate(_ aNotification: Notification) {
        timer?.invalidate()
    }

    @objc func checkForClipboardChanges() {
        let currentClipboardContents = getClipboardContents()
        if lastClipboardContents != currentClipboardContents {
            lastClipboardContents = currentClipboardContents
            requestGPTResponse(with: currentClipboardContents) { [weak self] response in
                self?.gptResponse = response
                self?.constructMenu()  // Refresh the menu
            }
        }
    }

    func constructMenu() {
        let menu = NSMenu()

        if let response = gptResponse {
            let chunkSize = 50  // Display around 50 characters per menu item. Adjust as needed.

            var startIndex = response.startIndex

            while startIndex < response.endIndex {
                let menuEndIndex = response.index(startIndex, offsetBy: chunkSize, limitedBy: response.endIndex) ?? response.endIndex
                let menuItemText = String(response[startIndex..<menuEndIndex])

                let menuItem = NSMenuItem()
                menuItem.title = menuItemText
                menu.addItem(menuItem)

                startIndex = menuEndIndex
            }

        } else {
            let menuItem = NSMenuItem(title: "No recent response", action: nil, keyEquivalent: "")
            menu.addItem(menuItem)
        }

        menu.addItem(NSMenuItem.separator())

        let menuItem2 = NSMenuItem()
        menuItem2.title = "Quit Mkill"
        menuItem2.action = #selector(NSApplication.terminate(_:))
        menu.addItem(menuItem2)

        statusItem?.menu = menu
    }

    
    func constructExamMenu() {
            let menu = NSMenu()

            for item in costExam {
                let trimmedQuestion = item["question"]!.prefix(50)  // Only take the first 50 characters of the question.
                let menuItem = NSMenuItem()
                menuItem.title = String(trimmedQuestion)
                menuItem.toolTip = item["answer"]
                menu.addItem(menuItem)
            }

            menu.addItem(NSMenuItem.separator())

            let menuItem2 = NSMenuItem()
            menuItem2.title = "Quit Mkill"
            menuItem2.action = #selector(NSApplication.terminate(_:))
            menu.addItem(menuItem2)

            statusItem?.menu = menu
    }

    
    func getClipboardContents() -> String {
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    func requestGPTResponse(with input: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": input]
            ],
            "max_tokens": 300
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: .fragmentsAllowed)
        } catch {
            print("JSON serialization error: \(error)")
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            } else if let data = data {
                print("Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode response")")
                let decoder = JSONDecoder()
                do {
                    let apiResponse = try decoder.decode(GPTChatResponse.self, from: data)
                    let text = apiResponse.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        completion(text)
                    }
                } catch {
                    if let apiError = try? decoder.decode(APIError.self, from: data) {
                        print("API Error: \(apiError.error.message)")
                    } else {
                        print("Decoding error: \(error)")
                    }
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            }
        }

        task.resume()
    }

    func showContextMenu() {
        let mouseLocation = NSEvent.mouseLocation
        window.setFrame(NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 1), display: false)
        window.makeKeyAndOrderFront(nil)
        constructMenu()
        statusItem?.menu?.popUp(positioning: statusItem?.menu?.item(at: 0), at: NSPoint(x: 0, y: 0), in: window.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func showExamContextMenu() {
            let mouseLocation = NSEvent.mouseLocation
            window.setFrame(NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 1), display: false)
            window.makeKeyAndOrderFront(nil)
            constructExamMenu()
            statusItem?.menu?.popUp(positioning: statusItem?.menu?.item(at: 0), at: NSPoint(x: 0, y: 0), in: window.contentView)
            NSApp.activate(ignoringOtherApps: true)
    }
}

struct GPTChatResponse: Codable {
    struct Choice: Codable {
        let message: Message
    }
    struct Message: Codable {
        let content: String
    }
    let choices: [Choice]
}

struct APIError: Codable {
    let error: ErrorDetails
    
    struct ErrorDetails: Codable {
        let message: String
        let type: String
        let param: String?
        let code: String
    }
}

class TooltipWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}
