import XCTest
import Foundation
@testable import AstroViewingConditions

final class ISSServiceTests: XCTestCase {
    
    // MARK: - ISS Response Parsing
    
    let mockISSResponse = """
    {
      "info": {
        "satid": 25544,
        "satname": "ISS (ZARYA)",
        "transactionscount": 10,
        "passescount": 3
      },
      "passes": [
        {
          "startAz": 45.0,
          "startAzCompass": "NE",
          "startEl": 10,
          "startUTC": 1700000000,
          "maxAz": 90.0,
          "maxAzCompass": "E",
          "maxEl": 45.0,
          "maxUTC": 1700000300,
          "endAz": 135.0,
          "endAzCompass": "SE",
          "endEl": 10,
          "endUTC": 1700000600,
          "mag": -2.0,
          "duration": 300
        },
        {
          "startAz": 180.0,
          "startAzCompass": "S",
          "startEl": 5,
          "startUTC": 1700086400,
          "maxAz": 270.0,
          "maxAzCompass": "W",
          "maxEl": 30.0,
          "maxUTC": 1700086700,
          "endAz": 360.0,
          "endAzCompass": "N",
          "endEl": 5,
          "endUTC": 1700087200,
          "mag": -1.5,
          "duration": 420
        }
      ]
    }
    """
    
    func testISSPassParsing() throws {
        let data = mockISSResponse.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        let response = try decoder.decode(N2YOResponse.self, from: data)
        
        XCTAssertEqual(response.info.satid, 25544)
        XCTAssertEqual(response.info.satname, "ISS (ZARYA)")
        XCTAssertEqual(response.passes?.count, 2)
    }
    
    func testISSPassFields() throws {
        let data = mockISSResponse.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        let response = try decoder.decode(N2YOResponse.self, from: data)
        
        guard let passes = response.passes, let firstPass = passes.first else {
            XCTFail("No passes found")
            return
        }
        
        XCTAssertEqual(firstPass.startAz, 45.0)
        XCTAssertEqual(firstPass.startAzCompass, "NE")
        XCTAssertEqual(firstPass.startEl, 10)
        XCTAssertEqual(firstPass.maxEl, 45.0)
        XCTAssertEqual(firstPass.duration, 300)
    }
    
    func testISSPassSetTimeCalculation() {
        let riseTime = Date(timeIntervalSince1970: TimeInterval(1700000000))
        let duration: TimeInterval = 300
        
        let pass = ISSPass(
            riseTime: riseTime,
            duration: duration,
            maxElevation: 45.0
        )
        
        let expectedSetTime = riseTime.addingTimeInterval(duration)
        
        XCTAssertEqual(pass.setTime, expectedSetTime)
    }
    
    func testISSPassIdGeneration() {
        let pass1 = ISSPass(
            riseTime: Date(),
            duration: 300,
            maxElevation: 45.0
        )
        
        let pass2 = ISSPass(
            riseTime: Date(),
            duration: 300,
            maxElevation: 45.0
        )
        
        XCTAssertNotEqual(pass1.id, pass2.id)
    }
    
    // MARK: - Empty Response
    
    func testISSPassWithNoPasses() {
        let json = """
        {
          "info": {
            "satid": 25544,
            "satname": "ISS (ZARYA)",
            "transactionscount": 1,
            "passescount": 0
          },
          "passes": []
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        do {
            let response = try decoder.decode(N2YOResponse.self, from: data)
            XCTAssertTrue(response.passes?.isEmpty ?? true)
        } catch {
            XCTFail("Failed to decode: \(error)")
        }
    }
    
    func testISSPassWithNilPasses() {
        let json = """
        {
          "info": {
            "satid": 25544,
            "satname": "ISS (ZARYA)",
            "transactionscount": 1,
            "passescount": 0
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        do {
            let response = try decoder.decode(N2YOResponse.self, from: data)
            XCTAssertNil(response.passes)
        } catch {
            XCTFail("Failed to decode: \(error)")
        }
    }
    
    // MARK: - Error Handling
    
    func testISSErrorInvalidURL() {
        let error = ISSError.invalidURL
        
        XCTAssertNotNil(error.localizedDescription)
    }
    
    func testISSErrorInvalidResponse() {
        let error = ISSError.invalidResponse
        
        XCTAssertNotNil(error.localizedDescription)
    }
    
    func testISSErrorApiError() {
        let error = ISSError.apiError("Test error message")
        
        XCTAssertNotNil(error.localizedDescription)
    }
}
