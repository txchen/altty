import Foundation

protocol PersistenceAdapter: Sendable {}
struct UserDefaultsPersistenceAdapter: PersistenceAdapter {}
