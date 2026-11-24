import CoreData
import SwiftData
import XCTest
@testable import PowerJack

final class CloudKitSchemaExportTests: XCTestCase {
    @MainActor
    func testExportSchema() throws {
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: PowerJackSchema.modelTypes))
        let entities = try model.entities.map { entity in
            try ModelEntity(
                name: XCTUnwrap(entity.name),
                root: rootName(of: entity),
                attributes: entity.attributesByName.values
                    .filter { !$0.isTransient }
                    .sorted { $0.name < $1.name }
                    .map(ModelAttribute.init),
                relationships: entity.relationshipsByName.values
                    .filter { !$0.isTransient }
                    .sorted { $0.name < $1.name }
                    .map { relationship in
                        try ModelRelationship(
                            name: relationship.name,
                            toMany: relationship.isToMany,
                            inverseToMany: XCTUnwrap(relationship.inverseRelationship).isToMany
                        )
                    }
            )
        }
        XCTAssertFalse(entities.isEmpty)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(
            data: try encoder.encode(entities.sorted { $0.name < $1.name }),
            uniformTypeIdentifier: "public.json"
        )
        attachment.name = "CloudKitModel"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func rootName(of entity: NSEntityDescription) throws -> String {
        if let parent = entity.superentity {
            return try rootName(of: parent)
        }
        return try XCTUnwrap(entity.name)
    }

    private struct ModelEntity: Encodable {
        let name: String
        let root: String
        let attributes: [ModelAttribute]
        let relationships: [ModelRelationship]
    }

    private struct ModelAttribute: Encodable {
        let name: String
        let type: String
        let encrypted: Bool

        init(_ attribute: NSAttributeDescription) throws {
            name = attribute.name
            encrypted = attribute.allowsCloudEncryption
            switch attribute.attributeType {
            case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType, .booleanAttributeType:
                type = "INT64"
            case .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
                type = "DOUBLE"
            case .stringAttributeType:
                type = "STRING+ASSET"
            case .UUIDAttributeType, .URIAttributeType:
                type = "STRING"
            case .dateAttributeType:
                type = "TIMESTAMP"
            case .binaryDataAttributeType, .transformableAttributeType:
                type = "BYTES+ASSET"
            case .compositeAttributeType:
                // Core Data archives a composite dictionary into a single record field.
                type = "BYTES"
            default:
                throw SchemaExportError.unsupportedAttribute(attribute.name, attribute.attributeType.rawValue)
            }
        }
    }

    private struct ModelRelationship: Encodable {
        let name: String
        let toMany: Bool
        let inverseToMany: Bool
    }

    private enum SchemaExportError: Error {
        case unsupportedAttribute(String, UInt)
    }
}
