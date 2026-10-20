//
//  ScaleSelectorOption.swift
//  PowerJack
//
//  A 0–5 rating, such as effort or pain. Kept apart from `ScaleSelector` so the watch app shares it.
//

protocol ScaleSelectorOption:
    CaseIterable,
    Hashable,
    RawRepresentable
where RawValue == Int {

    var label: String { get }
    /// The big value on the option. Defaults to the raw value.
    var valueText: String { get }
}

extension ScaleSelectorOption {
    var valueText: String { "\(rawValue)" }
}
