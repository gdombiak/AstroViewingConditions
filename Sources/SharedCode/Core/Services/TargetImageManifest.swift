import Foundation

/// The curated, reviewable manifest for target imagery. No network lookup occurs at runtime.
public enum TargetImageManifest {
    public static let imagesByTargetID: [String: TargetImageCredit] = {
        let nasaLicense = URL(string: "https://www.nasa.gov/nasa-brand-center/images-and-media/")!
        let publicDomain = "NASA Public Domain"
        let verified = ISO8601DateFormatter().date(from: "2026-07-04T00:00:00Z")!

        func image(
            _ id: String,
            sourceName: String,
            sourceURL: String,
            credit: String,
            licenseName: String,
            licenseURL: URL,
            requiresAttribution: Bool,
            hasThumbnail: Bool = true,
            thumbnailAssetName: String? = nil,
            heroAssetName: String? = nil,
            displayName: String? = nil,
            objectName: String? = nil,
            commonsPageURL: String? = nil
        ) -> (String, TargetImageCredit) {
            (id, TargetImageCredit(
                targetID: id,
                assetName: "target-\(id)",
                thumbnailAssetName: hasThumbnail ? (thumbnailAssetName ?? "target-\(id)") : nil,
                sourceName: sourceName,
                sourceURL: URL(string: sourceURL)!,
                credit: credit,
                licenseName: licenseName,
                licenseURL: licenseURL,
                requiresAttribution: requiresAttribution,
                isVerified: true,
                verifiedAt: verified,
                displayName: displayName,
                objectName: objectName,
                commonsPageURL: commonsPageURL.flatMap(URL.init(string:)),
                heroAssetName: heroAssetName
            ))
        }

        return Dictionary(uniqueKeysWithValues: [
            image("moon", sourceName: "NASA Image and Video Library", sourceURL: "https://commons.wikimedia.org/wiki/File:Full_disc_of_moon_photographed_by_Apollo_17_crewmen_during_transearth_coast_(as17-152-23311).jpg", credit: "NASA Johnson Space Center", licenseName: publicDomain, licenseURL: nasaLicense, requiresAttribution: false),
            image("venus", sourceName: "NASA/JPL Photojournal", sourceURL: "https://commons.wikimedia.org/wiki/File:PIA00270_Venus_(Computer_Simulated_Global_View_Centered_at_90_Degrees_East_Longitude).jpg", credit: "NASA/JPL", licenseName: publicDomain, licenseURL: nasaLicense, requiresAttribution: false),
            image("mars", sourceName: "NASA/JPL Photojournal", sourceURL: "https://commons.wikimedia.org/wiki/File:MARS-Viking.jpg", credit: "NASA/JPL/USGS", licenseName: publicDomain, licenseURL: nasaLicense, requiresAttribution: false),
            image("jupiter", sourceName: "NASA/JPL Photojournal", sourceURL: "https://commons.wikimedia.org/wiki/File:(PIA20701)_Juno_on_Jupiter%27s_Doorstep.jpg", credit: "NASA/JPL-Caltech/SwRI/MSSS", licenseName: publicDomain, licenseURL: nasaLicense, requiresAttribution: false),
            image("saturn", sourceName: "NASA Photojournal", sourceURL: "https://science.nasa.gov/photojournal/saturn-in-color/", credit: "NASA/JPL/Space Science Institute", licenseName: publicDomain, licenseURL: nasaLicense, requiresAttribution: false, thumbnailAssetName: "target-saturn-thumbnail", displayName: "Saturn", objectName: "Saturn"),
            image("m57", sourceName: "NASA Spitzer Space Telescope", sourceURL: "https://commons.wikimedia.org/wiki/File:M57RingNebula.jpg", credit: "NASA/JPL-Caltech/J. Hora (Harvard-Smithsonian CfA)", licenseName: publicDomain, licenseURL: nasaLicense, requiresAttribution: false),
            image("m27", sourceName: "NASA Science", sourceURL: "https://science.nasa.gov/asset/hubble/vlt-image-of-dumbbell-nebula/", credit: "European Southern Observatory", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true, thumbnailAssetName: "target-m27-thumbnail", displayName: "M27 Dumbbell Nebula", objectName: "Dumbbell Nebula, M27, NGC 6853"),
            image("ngc7009", sourceName: "NASA/ESA Hubble", sourceURL: "https://commons.wikimedia.org/wiki/File:NGC_7009_Hubble.jpg", credit: "NASA, ESA and STScI", licenseName: "Public Domain (PD-Hubble)", licenseURL: nasaLicense, requiresAttribution: false),
            image("m11", sourceName: "ESO", sourceURL: "https://www.eso.org/public/images/eso1430a/", credit: "ESO", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true, thumbnailAssetName: "target-m11-thumbnail", displayName: "M11 Wild Duck Cluster", objectName: "Wild Duck Cluster, M11, NGC 6705"),
            image("m2", sourceName: "ESA/Hubble", sourceURL: "https://commons.wikimedia.org/wiki/File:Messier2_-_HST_-_Potw1913a.jpg", credit: "ESA/Hubble & NASA, G. Piotto et al.", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true),
            image("m52", sourceName: "NOIRLab / Wikimedia Commons", sourceURL: "https://noirlab.edu/public/images/noao-m52/", credit: "NOIRLab", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true, thumbnailAssetName: "target-m52-thumbnail", displayName: "M52 Open Cluster", objectName: "M52, NGC 7654", commonsPageURL: "https://commons.wikimedia.org/wiki/File:M52,_NGC_7654_(noao-m52).jpg"),
            image("m13", sourceName: "Wikimedia Commons", sourceURL: "https://commons.wikimedia.org/wiki/File:Hercules_globular_cluster_m13.jpg", credit: "Miodrag Sekulic", licenseName: "CC BY-SA 3.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/3.0/")!, requiresAttribution: true, thumbnailAssetName: "target-m13-thumbnail", heroAssetName: "target-m13-hero"),
            image("m31", sourceName: "ESA/Hubble", sourceURL: "https://commons.wikimedia.org/wiki/File:Andromeda_Galaxy_M31_-_Heic1502a_10k.jpg", credit: "NASA, ESA and the Hubble Heritage Team (STScI/AURA)", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true),
            image("m92", sourceName: "ESA/Hubble", sourceURL: "https://commons.wikimedia.org/wiki/File:Messier_92_(Hubble)_(2021-012-01EYXC08H7WCDRGQWW8E41JC89).png", credit: "ESA/Hubble & NASA; Gilles Chapdelaine", licenseName: publicDomain, licenseURL: nasaLicense, requiresAttribution: false),
            image("albireo", sourceName: "Wikimedia Commons", sourceURL: "https://commons.wikimedia.org/wiki/File:Albireo_-_Westview_Observatory.jpg", credit: "Charlemagne920", licenseName: "CC BY-SA 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!, requiresAttribution: true, thumbnailAssetName: "target-albireo-thumbnail", heroAssetName: "target-albireo-hero"),
            image("epsilon-lyrae", sourceName: "Wikimedia Commons", sourceURL: "https://commons.wikimedia.org/wiki/File:Epsilon_Lyrae_the_double-double.jpg", credit: "Nikolay Nikolov", licenseName: "CC BY-SA 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!, requiresAttribution: true, thumbnailAssetName: "target-epsilon-lyrae-thumbnail", heroAssetName: "target-epsilon-lyrae-hero"),
            image("m45", sourceName: "NASA Science / Hubble", sourceURL: "https://science.nasa.gov/asset/hubble/hubble-refines-distance-to-the-pleiades-star-cluster/", credit: "NASA, ESA and AURA/Caltech", licenseName: "NASA Media Usage Guidelines", licenseURL: nasaLicense, requiresAttribution: true, displayName: "M45 Pleiades", objectName: "Pleiades, NGC 1432/35, M45"),
            image("m42", sourceName: "NASA Science / Hubble", sourceURL: "https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-messier-catalog/messier-42/", credit: "NASA, ESA, M. Robberto (STScI/ESA) and the Hubble Space Telescope Orion Treasury Project Team", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true, displayName: "M42 Orion Nebula", objectName: "Orion Nebula, M42"),
            image("m5", sourceName: "NASA Science / Hubble", sourceURL: "https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-messier-catalog/messier-5/", credit: "NASA, ESA, G. Piotto (Universita degli Studi di Padova); Image Processing: Gladys Kober (NASA/Catholic University of America)", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true, displayName: "M5 Globular Cluster", objectName: "Messier 5"),
            image("m3", sourceName: "NASA Science / Hubble", sourceURL: "https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-messier-catalog/messier-3/", credit: "ESA/Hubble & NASA, G. Piotto et al.", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true, displayName: "M3 Globular Cluster", objectName: "Messier 3"),
            image("m33", sourceName: "NASA Science / Hubble", sourceURL: "https://science.nasa.gov/mission/hubble/science/explore-the-night-sky/hubble-messier-catalog/messier-33/", credit: "NASA, ESA, and M. Durbin, J. Dalcanton and B. F. Williams (University of Washington)", licenseName: "CC BY 4.0", licenseURL: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, requiresAttribution: true, thumbnailAssetName: "target-m33-thumbnail", displayName: "M33 Triangulum Galaxy", objectName: "Messier 33, Triangulum Galaxy")
        ])
    }()

    public static func image(for targetID: String) -> TargetImageCredit? {
        imagesByTargetID[targetID.lowercased()]
    }
}
