import Foundation
import Translation

struct TranslationInput: Decodable {
  let id: String
  let text: String
}

struct TranslationOutput: Encodable {
  let id: String
  let text: String
}

let decoder = JSONDecoder()
let encoder = JSONEncoder()
let inputData = FileHandle.standardInput.readDataToEndOfFile()
let inputs = try String(decoding: inputData, as: UTF8.self)
  .split(separator: "\n")
  .map { try decoder.decode(TranslationInput.self, from: Data($0.utf8)) }
let session = TranslationSession(
  installedSource: Locale(identifier: "ja").language,
  target: Locale(identifier: "zh-Hans").language
)

for start in stride(from: 0, to: inputs.count, by: 32) {
  let batch = inputs[start..<min(start + 32, inputs.count)]
  let requests = batch.map {
    TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id)
  }
  for response in try await session.translations(from: requests) {
    let output = TranslationOutput(
      id: response.clientIdentifier ?? "",
      text: response.targetText
    )
    FileHandle.standardOutput.write(try encoder.encode(output))
    FileHandle.standardOutput.write(Data([0x0A]))
  }
}
