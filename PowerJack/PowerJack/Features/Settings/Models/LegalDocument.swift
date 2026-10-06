//
//  LegalDocument.swift
//  PowerJack
//

import Foundation

// A titled legal page shown from Settings. Keep the privacy policy in sync with PRIVACY.md.
struct LegalDocument: Hashable {
    struct Section: Hashable {
        let heading: String
        let body: String
    }

    let title: String
    let lastUpdated: String
    let sections: [Section]
}

extension LegalDocument {
    static let privacyPolicy = LegalDocument(
        title: "Privacy Policy",
        lastUpdated: "October 6, 2026",
        sections: [
            Section(
                heading: "The Short Version",
                body: "PowerJack does not collect, sell or share any of your data. There are no accounts, no ads, no analytics and no tracking."
            ),
            Section(
                heading: "What Stays on Your iPhone",
                body: "Your programs, templates, exercises, workout history and settings are stored on your iPhone. The developer never sees them."
            ),
            Section(
                heading: "iCloud Backup",
                body: "If iCloud Backup is on, PowerJack keeps a copy of your data in your own private iCloud database, so a new iPhone or a reinstall can restore it. Only your Apple Account can read that copy, and Apple handles it under Apple's Privacy Policy. Turning iCloud Backup off deletes the iCloud copy."
            ),
            Section(
                heading: "Live Activities",
                body: "The rest timer on the Lock Screen and in the Dynamic Island runs on your iPhone. Nothing about it leaves the device."
            ),
            Section(
                heading: "Third Parties",
                body: "PowerJack contains no third-party code, SDKs or services."
            ),
            Section(
                heading: "Children",
                body: "PowerJack is intended only for adults 18 and older."
            ),
            Section(
                heading: "Open Source",
                body: "PowerJack is open source, so anyone can check this policy against the code at https://github.com/it-is-i-lobster-tail/PowerJack."
            ),
            Section(
                heading: "Changes and Contact",
                body: "If this policy changes, the new version will be posted with a new date. Questions can be raised as an issue on the PowerJack GitHub repository."
            ),
        ]
    )

    static let termsAndConditions = LegalDocument(
        title: "Terms and Conditions",
        lastUpdated: "October 5, 2026",
        sections: [
            Section(
                heading: "Agreement",
                body: "By using PowerJack you agree to these terms. If you do not agree, do not use the app."
            ),
            Section(
                heading: "Adults Only",
                body: "PowerJack is only for people 18 and older. By using it, you confirm that you are at least 18."
            ),
            Section(
                heading: "Not Medical Advice",
                body: "PowerJack is a workout log, not a doctor, coach or physical therapist. Nothing in the app is medical, health or professional fitness advice, and it does not diagnose, treat or prevent any condition."
            ),
            Section(
                heading: "See a Medical Provider First",
                body: "Talk to a doctor or other qualified medical provider before starting any training program, and before changing one. This matters most if you are pregnant, injured, recovering from surgery, taking medication, or have any heart, blood pressure, joint or other health condition."
            ),
            Section(
                heading: "Train at Your Own Risk",
                body: "Strength training, especially hard training close to failure, carries a real risk of injury, illness and death. You choose your exercises, weights, sets, reps and rest, and you voluntarily accept every risk of training, whether or not you follow anything shown in the app."
            ),
            Section(
                heading: "Stop if Something Is Wrong",
                body: "Stop exercising right away if you feel pain, chest pain or pressure, shortness of breath, dizziness, faintness, nausea, numbness, or anything else that feels wrong. Get medical help if it does not pass quickly. Do not train through pain."
            ),
            Section(
                heading: "Train Safely",
                body: "Follow all rules, posted instructions and staff directions at your gym. Follow the manufacturer's instructions for all equipment and check it before use. Use proper form, collars, safety pins or arms, and a spotter for heavy or near-failure sets. Warm up, stay within your ability, and never train alone in a way that could trap you under a weight."
            ),
            Section(
                heading: "No Guarantees",
                body: "Progression, rest times and other suggestions in PowerJack are general and may not suit you. Results are not guaranteed. Use your own judgment and adjust or skip anything that is not right for you."
            ),
            Section(
                heading: "Provided As Is",
                body: "PowerJack is provided free and \"as is\", without warranties of any kind, express or implied, including fitness for a particular purpose. The app may contain errors, and your data may be lost. Keep your own records of anything important."
            ),
            Section(
                heading: "Limitation of Liability",
                body: "To the fullest extent allowed by law, the developer and contributors are not liable for any injury, illness, death, loss of data, or any direct, indirect, incidental or consequential damages arising from your use of PowerJack or from any exercise you do. You release them from all such claims."
            ),
            Section(
                heading: "Changes",
                body: "These terms may change. Using PowerJack after a change means you accept the new terms. If any part of these terms cannot be enforced, the rest still applies."
            ),
        ]
    )
}
