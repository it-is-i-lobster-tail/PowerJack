import Foundation
import SwiftData
import Testing
@testable import PowerJack

@MainActor
struct SharingTests {
    /// The sender's phone and the receiver's phone.
    let senderContainer: ModelContainer
    let receiverContainer: ModelContainer
    var sender: ModelContext { senderContainer.mainContext }
    var receiver: ModelContext { receiverContainer.mainContext }

    init() throws {
        senderContainer = try PowerJackSchema.makeModelContainer(inMemory: true)
        receiverContainer = try PowerJackSchema.makeModelContainer(inMemory: true)
        try ExerciseCatalog.seed(in: senderContainer.mainContext)
        try ExerciseCatalog.seed(in: receiverContainer.mainContext)
    }

    private func builtIn(_ catalogID: String, in context: ModelContext) throws -> Exercise {
        try #require(try context.fetch(FetchDescriptor<Exercise>()).first { $0.catalogID == catalogID })
    }

    @discardableResult
    private func own(_ name: String, minReps: Int = 8, maxReps: Int = 12, in context: ModelContext) throws -> Exercise {
        let exercise = Exercise(exerciseName: name, exerciseEquipment: .cable, primaryMuscleFocus: .chest,
                                secondaryMuscles: [.shoulders], userCreated: true, minReps: minReps, maxReps: maxReps)
        context.insert(exercise)
        try context.save()
        return exercise
    }

    /// Two days: a built-in, then the lifter's own lift in a superset with the built-in.
    private func sharedTemplate() throws -> (TemplateProgram, Exercise, Exercise) {
        let row = try builtIn("barbell-row", in: sender)
        let fly = try own("Low Cable Fly", in: sender)
        MovesLike.copy("catalog:barbell-row", to: fly, in: sender)
        let template = TemplateProgram(templateName: "Push Pull", workoutsPerWeek: 2,
                                       templateMuscleFocus: [.chest, .back], templateType: .strength)
        sender.insert(template)
        template.addTemplateWorkout().addTemplateExercise(exercise: row)
        let superset = UUID()
        let dayTwo = template.addTemplateWorkout()
        dayTwo.addTemplateExercise(exercise: fly, supersetID: superset)
        dayTwo.addTemplateExercise(exercise: row, supersetID: superset)
        try sender.save()
        return (template, row, fly)
    }

    /// The file as it arrives: encoded on one phone, decoded on the other.
    private func received(_ file: SharedFile) throws -> SharedImport {
        try SharedImport(file: SharedFile.decode(file.encoded()), in: receiver)
    }

    private func exercises(named name: String) throws -> [Exercise] {
        try receiver.fetch(FetchDescriptor<Exercise>()).filter { $0.exerciseName == name }
    }

    @Test("A shared template arrives with its days, supersets and the sender's own exercises")
    func templateRoundTrip() throws {
        let (template, _, senderFly) = try sharedTemplate()
        let file = SharedFile(template: template)
        #expect(file.exercises.count == 2)

        let sharedImport = try received(file)
        #expect(sharedImport.itemsToShow.map(\.shared.name) == ["Low Cable Fly"])
        #expect(!sharedImport.items.contains(where: \.asks))

        let imported = try #require(try sharedImport.save(in: receiver))
        #expect(imported.templateName == "Push Pull")
        #expect(imported.templateType == .strength)
        #expect(imported.workoutsPerWeek == 2)
        #expect(imported.templateMuscleFocus == [.back, .chest])
        #expect(!imported.draft)

        let days = imported.templateWorkouts.map { $0.templateExercises.compactMap(\.exercise) }
        let receiverRow = try builtIn("barbell-row", in: receiver)
        let fly = try #require(try exercises(named: "Low Cable Fly").first)
        #expect(days[0] == [receiverRow])
        #expect(days[1] == [fly, receiverRow])

        // One superset, with a new ID, so it never links to the sender's.
        let supersets = imported.templateWorkouts[1].templateExercises.map(\.supersetID)
        #expect(supersets[0] != nil && supersets[0] == supersets[1])
        #expect(supersets[0] != template.templateWorkouts[1].templateExercises[0].supersetID)

        #expect(fly.userCreated)
        #expect(fly.equipment == .cable)
        #expect(fly.primaryMuscleFocus == .chest)
        #expect(fly.secondaryMuscles == [.shoulders])
        #expect(fly.repRange == 8...12)
        #expect(fly.syncIDValue != nil && fly.syncIDValue != senderFly.syncIDValue)
        #expect(MovesLike.key(of: fly) == "catalog:barbell-row")
        #expect(!(fly.jointActions ?? []).isEmpty)
    }

    @Test("An exercise the receiver already has, set up the same, is used without asking")
    func identicalExerciseIsReused() throws {
        let fly = try own("Low Cable Fly", in: sender)
        let mine = try own("low cable fly ", in: receiver)

        let sharedImport = try received(SharedFile(exercise: fly))
        #expect(sharedImport.items.first?.existing === mine)
        #expect(sharedImport.hasNothingToAdd)
    }

    @Test("A name clash uses the receiver's exercise unless they keep both")
    func nameClash() throws {
        let (template, _, _) = try sharedTemplate()
        let mine = try own("Low Cable Fly", minReps: 10, maxReps: 15, in: receiver)

        var sharedImport = try received(SharedFile(template: template))
        let clash = try #require(sharedImport.items.firstIndex(where: \.asks))
        #expect(sharedImport.items[clash].choice == .useMine)
        #expect(sharedImport.items[clash].keepBothName == "Low Cable Fly 2")

        let usingMine = try #require(try sharedImport.save(in: receiver))
        #expect(usingMine.templateWorkouts[1].templateExercises.first?.exercise === mine)
        #expect(try exercises(named: "Low Cable Fly").count == 1)
        #expect(mine.repRange == 10...15)

        sharedImport.items[clash].choice = .keepBoth
        let keepingBoth = try #require(try sharedImport.save(in: receiver))
        let added = try #require(try exercises(named: "Low Cable Fly 2").first)
        #expect(added.repRange == 8...12)
        #expect(keepingBoth.templateWorkouts[1].templateExercises.first?.exercise === added)
        #expect(mine.repRange == 10...15)
        // The second copy of the template gets its own name.
        #expect(keepingBoth.templateName == "Push Pull 2")
    }

    @Test("A single shared exercise is added under its own name")
    func singleExercise() throws {
        let press = try own("Landmine Press", in: sender)
        let sharedImport = try received(SharedFile(exercise: press))
        #expect(sharedImport.template == nil)
        #expect(!sharedImport.hasNothingToAdd)
        #expect(try sharedImport.save(in: receiver) == nil)
        #expect(try exercises(named: "Landmine Press").count == 1)
    }

    @Test("Files from a newer version, or that aren't PowerJack files, are refused")
    func unreadableFiles() throws {
        #expect(throws: SharedFileError.unreadable) { try SharedFile.decode(Data("hello".utf8)) }
        #expect(throws: SharedFileError.newerVersion) { try SharedFile.decode(Data(#"{"version": 99}"#.utf8)) }

        let press = try own("Landmine Press", in: sender)
        var file = SharedFile(exercise: press)
        file.exercises[0].equipment = "hoverboard"
        #expect(throws: SharedFileError.newerVersion) { try received(file) }
    }

    @Test("Keep Both names count up and still fit the name limit")
    func uniqueNames() {
        let taken: Set = ["bench", "bench 2"]
        #expect(SharedImport.uniqueName("Bench", maxLength: 30, taken: taken) == "Bench 3")
        #expect(SharedImport.uniqueName("Squat", maxLength: 30, taken: taken) == "Squat")
        let long = String(repeating: "a", count: 30)
        let unique = SharedImport.uniqueName(long, maxLength: 30, taken: [long])
        #expect(unique.count == 30 && unique.hasSuffix(" 2"))
    }

    @Test("The shared file is named after the template, safely")
    func fileName() {
        #expect(SharedFileItem(name: "Push/Pull: A", data: Data()).fileName == "Push-Pull- A.powerjack")
        #expect(SharedFileItem(name: "  ", data: Data()).fileName == "PowerJack.powerjack")
    }
}
