//
//  GoogleDriveUtils.swift
//  EagleViewer
//
//  Created on 2025/09/28
//

import GoogleAPIClientForREST_Drive

enum GoogleDriveUtils {
    static func getChildFileId(service: GTLRDriveService, folderId: String, fileName: String) async throws -> String {
        let query = GTLRDriveQuery_FilesList.query()
        query.q = """
            '\(folderId)' in parents \
            and name = '\(fileName)' \
            and trashed = false
        """
        query.spaces = "drive"
        query.pageSize = 1
        query.fields = "files(id)"

        return try await withCheckedThrowingContinuation { cont in
            service.executeQuery(query) { _, result, error in
                if let error { return cont.resume(throwing: error) }
                guard
                    let list = result as? GTLRDrive_FileList,
                    let file = list.files?.first,
                    let id = file.identifier
                else {
                    return cont.resume(throwing: LibrarySelectionError.metadataNotFound)
                }
                cont.resume(returning: id)
            }
        }
    }

    static func getFileData(service: GTLRDriveService, fileId: String) async throws -> Data {
        let query = GTLRDriveQuery_FilesGet.queryForMedia(withFileId: fileId)

        return try await withCheckedThrowingContinuation { cont in
            service.executeQuery(query) { _, result, error in
                if let error { return cont.resume(throwing: error) }
                guard let dataObj = result as? GTLRDataObject else {
                    return cont.resume(throwing: LibrarySelectionError.metadataNotFound)
                }
                cont.resume(returning: dataObj.data)
            }
        }
    }
}
