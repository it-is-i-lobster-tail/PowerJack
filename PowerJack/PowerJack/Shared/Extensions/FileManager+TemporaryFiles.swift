//
//  FileManager+TemporaryFiles.swift
//  PowerJack
//
//  Clears files PowerJack wrote to the temporary directory earlier, which iOS only empties now and then.
//

import Foundation

extension FileManager {
    /// Deletes files in the temporary directory whose names start with `prefix` and end with `suffix`.
    /// Nothing else there is touched.
    func removeTemporaryFiles(prefix: String, suffix: String) {
        let folder = URL.temporaryDirectory
        guard let names = try? contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return }
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(suffix) {
            try? removeItem(at: folder.appending(path: name))
        }
    }
}
