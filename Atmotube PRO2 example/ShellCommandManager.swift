import Foundation
import iOSMcuManagerLibrary

actor ShellCommandManager {
    private let transport: McuMgrBleTransport
    
    init(transport: McuMgrBleTransport) {
        self.transport = transport
    }
    
    func sendCommand(_ command: String) async -> String {
        let shellManager = ShellManager(transport: transport)
        
        return await withCheckedContinuation { continuation in
            // Split command into cmd and args
            let parts = command.split(separator: " ").map { String($0) }
            guard !parts.isEmpty else {
                continuation.resume(returning: "Empty command")
                return
            }
            
            let cmd = parts[0]
            let args = parts.dropFirst().isEmpty ? [] : Array(parts.dropFirst())
            
            shellManager.execute(command: cmd, arguments: args) { (response: McuMgrResponse?, error: Error?) in
                if let error = error {
                    continuation.resume(returning: "Error: \(error.localizedDescription)")
                    return
                }
                
                if let response = response {
                    if let output = (response as? McuMgrExecResponse)?.output {
                        continuation.resume(returning: output)
                    } else if let ret = (response as? McuMgrExecResponse)?.rc {
                        continuation.resume(returning: "RC: \(ret)")
                    } else {
                        continuation.resume(returning: "Success (no output)")
                    }
                } else {
                    continuation.resume(returning: "No response")
                }
            }
        }
    }
}
