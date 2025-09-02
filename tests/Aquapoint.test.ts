
import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("Aquapoint Water Utility System", () => {
  beforeEach(() => {
    simnet.mineEmptyBlocks(1);
  });

  describe("Token Management", () => {
    it("should mint tokens to recipient", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "mint-tokens",
        [Cl.principal(wallet1), Cl.uint(1000)],
        deployer
      );
      expect(result).toBeOk(Cl.uint(1000));
      
      const balance = simnet.callReadOnlyFn(
        "Aquapoint",
        "get-token-balance",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(balance.result).toBeUint(1000);
    });

    it("should prevent unauthorized token minting", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "mint-tokens",
        [Cl.principal(wallet1), Cl.uint(1000)],
        wallet1
      );
      expect(result).toBeErr(Cl.uint(100)); // ERR_UNAUTHORIZED
    });

    it("should allow token purchasing", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "purchase-tokens",
        [Cl.uint(500)],
        wallet1
      );
      expect(result).toBeOk(Cl.uint(500));
    });

    it("should transfer tokens between users", () => {
      // First mint tokens to wallet1
      simnet.callPublicFn(
        "Aquapoint",
        "mint-tokens",
        [Cl.principal(wallet1), Cl.uint(1000)],
        deployer
      );

      // Transfer tokens from wallet1 to wallet2
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "transfer-tokens",
        [Cl.principal(wallet2), Cl.uint(300)],
        wallet1
      );
      expect(result).toBeOk(Cl.uint(300));
    });
  });

  describe("Smart Meter Management", () => {
    it("should register smart meter", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "register-smart-meter",
        [Cl.stringAscii("METER001"), Cl.stringAscii("123 Main St")],
        wallet1
      );
      expect(result).toBeOk(Cl.stringAscii("METER001"));

      const meterInfo = simnet.callReadOnlyFn(
        "Aquapoint",
        "get-meter-info",
        [Cl.stringAscii("METER001")],
        deployer
      );
      expect(meterInfo.result).toBeSome();
    });

    it("should prevent duplicate meter registration", () => {
      // Register meter first time
      simnet.callPublicFn(
        "Aquapoint",
        "register-smart-meter",
        [Cl.stringAscii("METER001"), Cl.stringAscii("123 Main St")],
        wallet1
      );

      // Try to register same meter again
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "register-smart-meter",
        [Cl.stringAscii("METER001"), Cl.stringAscii("456 Oak Ave")],
        wallet2
      );
      expect(result).toBeErr(Cl.uint(104)); // ERR_ALREADY_REGISTERED
    });

    it("should deactivate and reactivate meter", () => {
      // Register meter
      simnet.callPublicFn(
        "Aquapoint",
        "register-smart-meter",
        [Cl.stringAscii("METER002"), Cl.stringAscii("789 Pine St")],
        wallet1
      );

      // Deactivate meter
      const deactivate = simnet.callPublicFn(
        "Aquapoint",
        "deactivate-meter",
        [Cl.stringAscii("METER002")],
        wallet1
      );
      expect(deactivate.result).toBeOk(Cl.bool(true));

      // Reactivate meter
      const reactivate = simnet.callPublicFn(
        "Aquapoint",
        "reactivate-meter",
        [Cl.stringAscii("METER002")],
        wallet1
      );
      expect(reactivate.result).toBeOk(Cl.bool(true));
    });
  });

  describe("Water Usage Reporting", () => {
    beforeEach(() => {
      // Setup: mint tokens and register meter
      simnet.callPublicFn(
        "Aquapoint",
        "mint-tokens",
        [Cl.principal(wallet1), Cl.uint(5000)],
        deployer
      );
      simnet.callPublicFn(
        "Aquapoint",
        "register-smart-meter",
        [Cl.stringAscii("METER003"), Cl.stringAscii("101 Water Ave")],
        wallet1
      );
    });

    it("should report water usage and charge tokens", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "report-water-usage",
        [Cl.stringAscii("METER003"), Cl.uint(100)],
        deployer // Smart meter would report usage
      );
      expect(result).toBeOk(Cl.uint(1000)); // 100 gallons * 10 tokens per gallon

      // Check that tokens were burned from user
      const balance = simnet.callReadOnlyFn(
        "Aquapoint",
        "get-token-balance",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(balance.result).toBeUint(4000); // 5000 - 1000
    });

    it("should fail if insufficient tokens", () => {
      // Try to use more water than tokens available
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "report-water-usage",
        [Cl.stringAscii("METER003"), Cl.uint(1000)], // 1000 gallons = 10000 tokens needed
        deployer
      );
      expect(result).toBeErr(Cl.uint(101)); // ERR_INSUFFICIENT_BALANCE
    });
  });

  describe("Conservation Program", () => {
    beforeEach(() => {
      // Initialize conservation tiers
      simnet.callPublicFn(
        "Aquapoint",
        "initialize-conservation-tiers",
        [],
        deployer
      );
    });

    it("should join conservation program", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "join-conservation-program",
        [Cl.uint(1000)], // baseline usage
        wallet1
      );
      expect(result).toBeOk(Cl.uint(1)); // season ID

      const conservationData = simnet.callReadOnlyFn(
        "Aquapoint",
        "get-user-conservation-data",
        [Cl.principal(wallet1), Cl.uint(1)],
        deployer
      );
      expect(conservationData.result).toBeSome();
    });

    it("should create seasonal challenge", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "create-seasonal-challenge",
        [
          Cl.stringAscii("Summer Water Challenge"),
          Cl.uint(1008), // duration in blocks
          Cl.uint(20),   // 20% reduction target
          Cl.uint(500)   // bonus reward
        ],
        deployer
      );
      expect(result).toBeOk(Cl.uint(1)); // season ID
    });
  });

  describe("Water Quality System", () => {
    beforeEach(() => {
      // Initialize quality standards and register meter
      simnet.callPublicFn(
        "Aquapoint",
        "initialize-quality-standards",
        [],
        deployer
      );
      simnet.callPublicFn(
        "Aquapoint",
        "register-smart-meter",
        [Cl.stringAscii("METER004"), Cl.stringAscii("Quality Test St")],
        wallet1
      );
    });

    it("should report water quality readings", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "report-water-quality",
        [
          Cl.stringAscii("METER004"),
          Cl.uint(75),  // pH level
          Cl.uint(25),  // chlorine level
          Cl.uint(30),  // turbidity
          Cl.uint(5)    // contaminant level
        ],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true)); // All standards passed
    });

    it("should create quality alert for poor quality", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "report-water-quality",
        [
          Cl.stringAscii("METER004"),
          Cl.uint(50),  // Low pH (below standard)
          Cl.uint(25),  // chlorine level
          Cl.uint(60),  // High turbidity
          Cl.uint(15)   // High contaminant level
        ],
        deployer
      );
      expect(result).toBeOk(Cl.bool(false)); // Standards failed
    });
  });

  describe("Smart Analytics System", () => {
    it("should generate usage report", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "generate-usage-report",
        [
          Cl.uint(1000), // start block
          Cl.uint(2000), // end block
          Cl.stringAscii("DISTRICT_A")
        ],
        deployer
      );
      expect(result).toBeOk();
    });

    it("should calculate optimal pricing", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "calculate-optimal-pricing",
        [Cl.uint(15)], // 15% conservation target
        deployer
      );
      expect(result).toBeOk();
    });

    it("should provide conservation insights", () => {
      // First join conservation program
      simnet.callPublicFn(
        "Aquapoint",
        "initialize-conservation-tiers",
        [],
        deployer
      );
      simnet.callPublicFn(
        "Aquapoint",
        "join-conservation-program",
        [Cl.uint(500)],
        wallet1
      );

      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "generate-conservation-insights",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk();
    });
  });

  describe("Read-Only Functions", () => {
    it("should get system overview", () => {
      const { result } = simnet.callReadOnlyFn(
        "Aquapoint",
        "get-system-overview",
        [],
        deployer
      );
      expect(result).toBeTuple();
    });

    it("should get token price", () => {
      const { result } = simnet.callReadOnlyFn(
        "Aquapoint",
        "get-token-price",
        [],
        deployer
      );
      expect(result).toBeUint(10); // Default price
    });

    it("should get total water consumed", () => {
      const { result } = simnet.callReadOnlyFn(
        "Aquapoint",
        "get-total-water-consumed",
        [],
        deployer
      );
      expect(result).toBeUint(0); // Initial value
    });
  });

  describe("Admin Functions", () => {
    it("should set token price", () => {
      const { result } = simnet.callPublicFn(
        "Aquapoint",
        "set-token-price",
        [Cl.uint(15)],
        deployer
      );
      expect(result).toBeOk(Cl.uint(15));

      const price = simnet.callReadOnlyFn(
        "Aquapoint",
        "get-token-price",
        [],
        deployer
      );
      expect(price.result).toBeUint(15);
    });

    it("should pause and unpause contract", () => {
      const pause = simnet.callPublicFn(
        "Aquapoint",
        "pause-contract",
        [],
        deployer
      );
      expect(pause.result).toBeOk(Cl.bool(true));

      const unpause = simnet.callPublicFn(
        "Aquapoint",
        "unpause-contract",
        [],
        deployer
      );
      expect(unpause.result).toBeOk(Cl.bool(true));
    });
  });
});

describe("WaterAllocation Emergency System", () => {
  describe("Emergency Management", () => {
    it("should declare water emergency", () => {
      const { result } = simnet.callPublicFn(
        "WaterAllocation",
        "declare-water-emergency",
        [
          Cl.stringAscii("drought"),
          Cl.uint(3), // severity level
          Cl.list([Cl.uint(1), Cl.uint(2)]), // affected regions
          Cl.uint(1000), // estimated duration
          Cl.uint(25) // 25% reduction required
        ],
        deployer
      );
      expect(result).toBeOk(Cl.uint(1)); // emergency ID
    });

    it("should create allocation region", () => {
      const { result } = simnet.callPublicFn(
        "WaterAllocation",
        "create-allocation-region",
        [
          Cl.stringAscii("Downtown District"),
          Cl.uint(10000), // population
          Cl.uint(50),    // area in sq km
          Cl.uint(500000), // base allocation
          Cl.uint(2)      // priority level
        ],
        deployer
      );
      expect(result).toBeOk(Cl.uint(1)); // region ID
    });

    it("should add supply source", () => {
      const { result } = simnet.callPublicFn(
        "WaterAllocation",
        "add-supply-source",
        [
          Cl.stringAscii("Main Reservoir"),
          Cl.stringAscii("reservoir"),
          Cl.uint(1000000), // max capacity
          Cl.list([Cl.uint(1), Cl.uint(2)]) // serving regions
        ],
        deployer
      );
      expect(result).toBeOk(Cl.uint(1)); // source ID
    });

    it("should calculate emergency allocations", () => {
      // First create emergency and regions
      simnet.callPublicFn(
        "WaterAllocation",
        "declare-water-emergency",
        [
          Cl.stringAscii("infrastructure-failure"),
          Cl.uint(4),
          Cl.list([Cl.uint(1)]),
          Cl.uint(500),
          Cl.uint(30)
        ],
        deployer
      );

      simnet.callPublicFn(
        "WaterAllocation",
        "create-allocation-region",
        [
          Cl.stringAscii("Emergency Zone"),
          Cl.uint(5000),
          Cl.uint(25),
          Cl.uint(250000),
          Cl.uint(1)
        ],
        deployer
      );

      const { result } = simnet.callPublicFn(
        "WaterAllocation",
        "calculate-emergency-allocations",
        [Cl.uint(1)], // emergency ID
        deployer
      );
      expect(result).toBeOk();
    });
  });

  describe("Supply Management", () => {
    beforeEach(() => {
      // Add supply source for testing
      simnet.callPublicFn(
        "WaterAllocation",
        "add-supply-source",
        [
          Cl.stringAscii("Test Reservoir"),
          Cl.stringAscii("reservoir"),
          Cl.uint(800000),
          Cl.list([Cl.uint(1)])
        ],
        deployer
      );
    });

    it("should update supply levels", () => {
      const { result } = simnet.callPublicFn(
        "WaterAllocation",
        "update-supply-levels",
        [
          Cl.uint(1), // source ID
          Cl.uint(600000), // new level
          Cl.uint(85) // quality rating
        ],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));
    });

    it("should trigger alert for low supply levels", () => {
      const { result } = simnet.callPublicFn(
        "WaterAllocation",
        "update-supply-levels",
        [
          Cl.uint(1),
          Cl.uint(100000), // Very low level (< 20% capacity)
          Cl.uint(80)
        ],
        deployer
      );
      expect(result).toBeOk(Cl.bool(true));
    });
  });

  describe("Conservation Programs", () => {
    beforeEach(() => {
      // Create emergency for conservation program
      simnet.callPublicFn(
        "WaterAllocation",
        "declare-water-emergency",
        [
          Cl.stringAscii("drought"),
          Cl.uint(2),
          Cl.list([Cl.uint(1)]),
          Cl.uint(2000),
          Cl.uint(20)
        ],
        deployer
      );
    });

    it("should create emergency conservation program", () => {
      const { result } = simnet.callPublicFn(
        "WaterAllocation",
        "create-emergency-conservation",
        [
          Cl.uint(1), // emergency ID
          Cl.uint(25), // 25% conservation target
          Cl.uint(5),  // incentive rate
          Cl.uint(1000) // duration
        ],
        deployer
      );
      expect(result).toBeOk();
    });

    it("should distribute emergency supplies", () => {
      const { result } = simnet.callPublicFn(
        "WaterAllocation",
        "distribute-emergency-supplies",
        [
          Cl.uint(1),
          Cl.stringAscii("bottled-water"),
          Cl.list([Cl.uint(1), Cl.uint(2)]),
          Cl.uint(10000) // volume
        ],
        deployer
      );
      expect(result).toBeOk();
    });
  });

  describe("Read-Only Functions", () => {
    it("should get system status", () => {
      const { result } = simnet.callReadOnlyFn(
        "WaterAllocation",
        "get-system-status",
        [],
        deployer
      );
      expect(result).toBeTuple();
    });

    it("should calculate supply adequacy", () => {
      const { result } = simnet.callReadOnlyFn(
        "WaterAllocation",
        "calculate-supply-adequacy",
        [],
        deployer
      );
      expect(result).toBeTuple();
    });

    it("should get drought level", () => {
      const { result } = simnet.callReadOnlyFn(
        "WaterAllocation",
        "get-drought-level",
        [],
        deployer
      );
      expect(result).toBeUint(0); // Initial value
    });
  });

  describe("Integration Tests", () => {
    it("should resolve emergency and restore allocations", () => {
      // Create emergency
      const emergencyResult = simnet.callPublicFn(
        "WaterAllocation",
        "declare-water-emergency",
        [
          Cl.stringAscii("contamination"),
          Cl.uint(3),
          Cl.list([Cl.uint(1)]),
          Cl.uint(1500),
          Cl.uint(15)
        ],
        deployer
      );
      expect(emergencyResult.result).toBeOk(Cl.uint(1));

      // Resolve emergency
      const resolveResult = simnet.callPublicFn(
        "WaterAllocation",
        "resolve-water-emergency",
        [Cl.uint(1)],
        deployer
      );
      expect(resolveResult.result).toBeOk(Cl.bool(true));
    });
  });
});
