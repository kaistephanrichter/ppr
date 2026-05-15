import Foundation

struct RemoteStatus: Decodable {
    let pngxVersion: String
    let serverOs: String?
    let installType: String?
    let storage: RemoteStorageSummary?
    let database: RemoteDatabaseSummary?
    let tasks: RemoteTasksSummary?
}

struct RemoteStorageSummary: Decodable {
    let total: Int64?
    let available: Int64?
}

struct RemoteDatabaseSummary: Decodable {
    let type: String?
    let url: String?
    let status: String?
    let error: String?
    let migrationStatus: RemoteMigrationStatus?
}

struct RemoteMigrationStatus: Decodable {
    let latestMigration: String?
    let unappliedMigrations: [String]?
}

struct RemoteTasksSummary: Decodable {
    let redisStatus: String?
    let redisError: String?
    let celeryStatus: String?
    let celeryError: String?
    let indexStatus: String?
    let indexLastModified: String?
    let indexError: String?
    let classifierStatus: String?
    let classifierLastTrained: String?
    let classifierError: String?
    let sanityCheckStatus: String?
    let sanityCheckLastRun: String?
    let sanityCheckError: String?
}

struct RemoteStatistics: Decodable {
    let documentsTotal: Int?
    let documentsInbox: Int?
    let tagCount: Int?
    let correspondentCount: Int?
    let documentTypeCount: Int?
    let characterCount: Int?
}
