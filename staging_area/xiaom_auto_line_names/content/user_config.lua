-- Edit this file, restart TF3, then click Reload configuration in the line manager.
-- Applied values are stored in each savegame and survive mod updates.
-- Supported placeholders: transportType, serviceType, cargoTypes, placeA, placeB, lineType, lineNumber.
-- Cargo override keys are resource basenames (coal) or full names (::/cargo/coal.cargo).
return {
    passengerTemplate = "[{transportType}{serviceType}] {placeA}-{placeB}-{lineNumber}",
    freightTemplate = "[{transportType}{serviceType}] {cargoTypes}-{placeA}-{placeB}-{lineNumber}",
    numberWidth = 3,
    shortLength = 3,
    cargoLimit = 3,
    labels = {}, -- e.g. zh_CN = { train = "火车" }, en = { train = "Rail" }
    cargoOverrides = {}, -- e.g. coal = { short = "煤", code = "COAL" }
}
