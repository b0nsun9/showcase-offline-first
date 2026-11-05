import CoreData

enum StoreModel {
    /// Built once per process: Core Data warns when one entity belongs to two models.
    nonisolated(unsafe) static let shared = makeModel()

    static func makeModel() -> NSManagedObjectModel {
        func attr(_ name: String, _ type: NSAttributeType, optional: Bool = false, default value: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = optional
            a.defaultValue = value
            return a
        }

        let photo = attr("photo", .binaryDataAttributeType, optional: true)
        photo.allowsExternalBinaryDataStorage = true

        let job = NSEntityDescription()
        job.name = "JobEntity"
        job.managedObjectClassName = "NSManagedObject"
        job.properties = [
            attr("id", .stringAttributeType),
            attr("address", .stringAttributeType, default: ""),
            attr("task", .stringAttributeType, default: ""),
            attr("windowStart", .stringAttributeType, default: ""),
            attr("windowEnd", .stringAttributeType, default: ""),
            attr("position", .integer16AttributeType, default: 0),
            attr("completedAt", .dateAttributeType, optional: true),
            attr("note", .stringAttributeType, optional: true),
            photo,
            attr("photoBytes", .integer64AttributeType, default: 0),
            attr("photoSHA256", .stringAttributeType, optional: true),
            attr("serverCompleted", .booleanAttributeType, default: false),
        ]
        job.uniquenessConstraints = [["id"]]

        let outbox = NSEntityDescription()
        outbox.name = "OutboxEntity"
        outbox.managedObjectClassName = "NSManagedObject"
        outbox.properties = [
            attr("id", .UUIDAttributeType),
            attr("jobID", .stringAttributeType),
            attr("kind", .stringAttributeType),
            attr("idempotencyKey", .stringAttributeType, optional: true),
            attr("body", .binaryDataAttributeType, optional: true),
            attr("sequence", .integer64AttributeType, default: 0),
            attr("attempts", .integer32AttributeType, default: 0),
            attr("nextAttemptAt", .dateAttributeType, optional: true),
            attr("waitIsBackoff", .booleanAttributeType, default: false),
            attr("failed", .booleanAttributeType, default: false),
            attr("photoMismatches", .integer32AttributeType, default: 0),
        ]

        let model = NSManagedObjectModel()
        model.entities = [job, outbox]
        return model
    }
}
