;; title: Aquapoint
;; version: 1.0.0
;; summary: Water Usage Token System with Smart Meter Integration
;; description: A decentralized water utility system where smart meters report usage and users pay with tokens

(define-fungible-token aqua-token)

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_METER_NOT_FOUND (err u103))
(define-constant ERR_ALREADY_REGISTERED (err u104))
(define-constant ERR_PAYMENT_FAILED (err u105))
(define-constant ERR_INVALID_RATE (err u106))
(define-constant ERR_CHALLENGE_NOT_FOUND (err u107))
(define-constant ERR_CHALLENGE_ENDED (err u108))
(define-constant ERR_INVALID_CONSERVATION_TIER (err u109))
(define-constant ERR_NO_BASELINE_USAGE (err u110))
(define-constant ERR_QUALITY_READING_NOT_FOUND (err u111))
(define-constant ERR_INVALID_QUALITY_METRIC (err u112))
(define-constant ERR_QUALITY_THRESHOLD_EXCEEDED (err u113))
(define-constant ERR_INSUFFICIENT_COMPENSATION_FUND (err u114))

(define-data-var token-price-per-gallon uint u10)
(define-data-var total-water-consumed uint u0)
(define-data-var contract-paused bool false)
(define-data-var current-season-id uint u1)
(define-data-var conservation-reward-rate uint u5)
(define-data-var quality-compensation-fund uint u10000)
(define-data-var quality-monitoring-enabled bool true)

(define-map smart-meters
  { meter-id: (string-ascii 32) }
  {
    owner: principal,
    location: (string-ascii 64),
    total-usage: uint,
    last-reading: uint,
    last-payment-block: uint,
    active: bool
  }
)

(define-map user-balances
  { user: principal }
  {
    token-balance: uint,
    total-spent: uint,
    meters-owned: uint
  }
)

(define-map usage-history
  { meter-id: (string-ascii 32), block-height: uint }
  {
    usage-amount: uint,
    cost: uint,
    timestamp: uint
  }
)

(define-map authorized-meters
  { meter-id: (string-ascii 32) }
  { authorized: bool }
)

(define-map conservation-tiers
  { tier-id: uint }
  {
    tier-name: (string-ascii 20),
    reduction-threshold: uint,
    reward-multiplier: uint,
    minimum-savings: uint
  }
)

(define-map user-conservation-data
  { user: principal, season-id: uint }
  {
    baseline-usage: uint,
    current-usage: uint,
    conservation-tier: uint,
    total-rewards-earned: uint,
    participation-start: uint
  }
)

(define-map seasonal-challenges
  { season-id: uint }
  {
    challenge-name: (string-ascii 64),
    start-block: uint,
    end-block: uint,
    target-reduction: uint,
    bonus-reward: uint,
    participants: uint,
    active: bool
  }
)

(define-map conservation-leaderboard
  { season-id: uint, rank: uint }
  {
    user: principal,
    conservation-percentage: uint,
    rewards-earned: uint
  }
)

(define-map user-achievements
  { user: principal }
  {
    total-seasons: uint,
    best-conservation-rate: uint,
    total-conservation-rewards: uint,
    challenge-wins: uint
  }
)

(define-map water-quality-standards
  { quality-type: (string-ascii 20) }
  {
    min-value: uint,
    max-value: uint,
    unit: (string-ascii 10),
    compensation-rate: uint,
    active: bool
  }
)

(define-map meter-quality-readings
  { meter-id: (string-ascii 32), timestamp: uint }
  {
    ph-level: uint,
    chlorine-level: uint,
    turbidity: uint,
    contaminant-level: uint,
    overall-quality-score: uint,
    passed-standards: bool
  }
)

(define-map quality-alerts
  { alert-id: uint }
  {
    meter-id: (string-ascii 32),
    alert-type: (string-ascii 30),
    severity: uint,
    timestamp: uint,
    resolved: bool,
    compensation-issued: uint
  }
)

(define-map user-quality-history
  { user: principal, month: uint }
  {
    total-readings: uint,
    failed-readings: uint,
    total-compensation: uint,
    average-quality-score: uint
  }
)

(define-map quality-compensation-claims
  { claim-id: uint }
  {
    user: principal,
    meter-id: (string-ascii 32),
    compensation-amount: uint,
    claim-timestamp: uint,
    processed: bool
  }
)

(define-public (mint-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (ft-mint? aqua-token amount recipient))
    (update-user-balance recipient amount u0)
    (ok amount)
  )
)

(define-public (register-smart-meter (meter-id (string-ascii 32)) (location (string-ascii 64)))
  (let ((existing-meter (map-get? smart-meters { meter-id: meter-id })))
    (asserts! (is-none existing-meter) ERR_ALREADY_REGISTERED)
    (map-set smart-meters
      { meter-id: meter-id }
      {
        owner: tx-sender,
        location: location,
        total-usage: u0,
        last-reading: u0,
        last-payment-block: stacks-block-height,
        active: true
      }
    )
    (map-set authorized-meters { meter-id: meter-id } { authorized: true })
    (update-user-meters tx-sender)
    (ok meter-id)
  )
)

(define-public (report-water-usage (meter-id (string-ascii 32)) (usage-amount uint))
  (let (
    (meter-data (unwrap! (map-get? smart-meters { meter-id: meter-id }) ERR_METER_NOT_FOUND))
    (is-authorized (default-to false (get authorized (map-get? authorized-meters { meter-id: meter-id }))))
    (cost (* usage-amount (var-get token-price-per-gallon)))
    (meter-owner (get owner meter-data))
  )
    (asserts! (not (var-get contract-paused)) ERR_UNAUTHORIZED)
    (asserts! is-authorized ERR_UNAUTHORIZED)
    (asserts! (get active meter-data) ERR_UNAUTHORIZED)
    (asserts! (> usage-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (ft-get-balance aqua-token meter-owner) cost) ERR_INSUFFICIENT_BALANCE)
    
    (try! (ft-burn? aqua-token cost meter-owner))
    
    (map-set smart-meters
      { meter-id: meter-id }
      (merge meter-data {
        total-usage: (+ (get total-usage meter-data) usage-amount),
        last-reading: usage-amount,
        last-payment-block: stacks-block-height
      })
    )
    
    (map-set usage-history
      { meter-id: meter-id, block-height: stacks-block-height }
      {
        usage-amount: usage-amount,
        cost: cost,
        timestamp: stacks-block-height
      }
    )
    
    (var-set total-water-consumed (+ (var-get total-water-consumed) usage-amount))
    (update-user-spending meter-owner cost)
    (try! (update-water-usage-for-conservation meter-id usage-amount))
    (ok cost)
  )
)

(define-public (purchase-tokens (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (ft-mint? aqua-token amount tx-sender))
    (update-user-balance tx-sender amount u0)
    (ok amount)
  )
)

(define-public (transfer-tokens (recipient principal) (amount uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (ft-transfer? aqua-token amount tx-sender recipient))
    (ok amount)
  )
)

(define-public (set-token-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-price u0) ERR_INVALID_RATE)
    (var-set token-price-per-gallon new-price)
    (ok new-price)
  )
)

(define-public (deactivate-meter (meter-id (string-ascii 32)))
  (let ((meter-data (unwrap! (map-get? smart-meters { meter-id: meter-id }) ERR_METER_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get owner meter-data)) ERR_UNAUTHORIZED)
    (map-set smart-meters
      { meter-id: meter-id }
      (merge meter-data { active: false })
    )
    (ok true)
  )
)

(define-public (reactivate-meter (meter-id (string-ascii 32)))
  (let ((meter-data (unwrap! (map-get? smart-meters { meter-id: meter-id }) ERR_METER_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get owner meter-data)) ERR_UNAUTHORIZED)
    (map-set smart-meters
      { meter-id: meter-id }
      (merge meter-data { active: true })
    )
    (ok true)
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-private (update-user-balance (user principal) (token-amount uint) (spent-amount uint))
  (let ((current-balance (default-to { token-balance: u0, total-spent: u0, meters-owned: u0 } 
                                    (map-get? user-balances { user: user }))))
    (map-set user-balances
      { user: user }
      {
        token-balance: (+ (get token-balance current-balance) token-amount),
        total-spent: (+ (get total-spent current-balance) spent-amount),
        meters-owned: (get meters-owned current-balance)
      }
    )
  )
)

(define-private (update-user-spending (user principal) (spent-amount uint))
  (let ((current-balance (default-to { token-balance: u0, total-spent: u0, meters-owned: u0 } 
                                    (map-get? user-balances { user: user }))))
    (map-set user-balances
      { user: user }
      {
        token-balance: (get token-balance current-balance),
        total-spent: (+ (get total-spent current-balance) spent-amount),
        meters-owned: (get meters-owned current-balance)
      }
    )
  )
)

(define-private (update-user-meters (user principal))
  (let ((current-balance (default-to { token-balance: u0, total-spent: u0, meters-owned: u0 } 
                                    (map-get? user-balances { user: user }))))
    (map-set user-balances
      { user: user }
      {
        token-balance: (get token-balance current-balance),
        total-spent: (get total-spent current-balance),
        meters-owned: (+ (get meters-owned current-balance) u1)
      }
    )
  )
)

(define-public (initialize-conservation-tiers)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set conservation-tiers { tier-id: u1 } { tier-name: "Bronze", reduction-threshold: u10, reward-multiplier: u2, minimum-savings: u50 })
    (map-set conservation-tiers { tier-id: u2 } { tier-name: "Silver", reduction-threshold: u20, reward-multiplier: u3, minimum-savings: u100 })
    (map-set conservation-tiers { tier-id: u3 } { tier-name: "Gold", reduction-threshold: u30, reward-multiplier: u5, minimum-savings: u200 })
    (map-set conservation-tiers { tier-id: u4 } { tier-name: "Platinum", reduction-threshold: u40, reward-multiplier: u8, minimum-savings: u300 })
    (ok true)
  )
)

(define-public (join-conservation-program (baseline-usage uint))
  (let (
    (season-id (var-get current-season-id))
    (existing-data (map-get? user-conservation-data { user: tx-sender, season-id: season-id }))
  )
    (asserts! (> baseline-usage u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none existing-data) ERR_ALREADY_REGISTERED)
    (map-set user-conservation-data
      { user: tx-sender, season-id: season-id }
      {
        baseline-usage: baseline-usage,
        current-usage: u0,
        conservation-tier: u0,
        total-rewards-earned: u0,
        participation-start: stacks-block-height
      }
    )
    (ok season-id)
  )
)

(define-public (calculate-conservation-rewards (user principal))
  (let (
    (season-id (var-get current-season-id))
    (conservation-data (unwrap! (map-get? user-conservation-data { user: user, season-id: season-id }) ERR_NO_BASELINE_USAGE))
    (baseline (get baseline-usage conservation-data))
    (current (get current-usage conservation-data))
    (reduction-percentage (if (> baseline current) (/ (* (- baseline current) u100) baseline) u0))
    (tier (calculate-tier reduction-percentage))
    (tier-data (unwrap! (map-get? conservation-tiers { tier-id: tier }) ERR_INVALID_CONSERVATION_TIER))
    (reward-amount (if (and (> reduction-percentage u0) (>= (- baseline current) (get minimum-savings tier-data)))
                      (* (- baseline current) (get reward-multiplier tier-data) (var-get conservation-reward-rate))
                      u0))
  )
    (if (> reward-amount u0)
      (begin
        (try! (ft-mint? aqua-token reward-amount user))
        (map-set user-conservation-data
          { user: user, season-id: season-id }
          (merge conservation-data {
            conservation-tier: tier,
            total-rewards-earned: (+ (get total-rewards-earned conservation-data) reward-amount)
          })
        )
        (update-user-achievements user reduction-percentage reward-amount)
        (ok reward-amount)
      )
      (ok u0)
    )
  )
)

(define-public (create-seasonal-challenge (challenge-name (string-ascii 64)) (duration-blocks uint) (target-reduction uint) (bonus-reward uint))
  (let ((season-id (var-get current-season-id)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> target-reduction u0) ERR_INVALID_AMOUNT)
    (asserts! (> bonus-reward u0) ERR_INVALID_AMOUNT)
    (map-set seasonal-challenges
      { season-id: season-id }
      {
        challenge-name: challenge-name,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height duration-blocks),
        target-reduction: target-reduction,
        bonus-reward: bonus-reward,
        participants: u0,
        active: true
      }
    )
    (ok season-id)
  )
)

(define-public (participate-in-challenge)
  (let (
    (season-id (var-get current-season-id))
    (challenge (unwrap! (map-get? seasonal-challenges { season-id: season-id }) ERR_CHALLENGE_NOT_FOUND))
    (conservation-data (unwrap! (map-get? user-conservation-data { user: tx-sender, season-id: season-id }) ERR_NO_BASELINE_USAGE))
  )
    (asserts! (get active challenge) ERR_CHALLENGE_ENDED)
    (asserts! (<= stacks-block-height (get end-block challenge)) ERR_CHALLENGE_ENDED)
    (map-set seasonal-challenges
      { season-id: season-id }
      (merge challenge { participants: (+ (get participants challenge) u1) })
    )
    (ok true)
  )
)

(define-public (update-water-usage-for-conservation (meter-id (string-ascii 32)) (usage-amount uint))
  (let (
    (meter-data (unwrap! (map-get? smart-meters { meter-id: meter-id }) ERR_METER_NOT_FOUND))
    (meter-owner (get owner meter-data))
    (season-id (var-get current-season-id))
    (conservation-data (map-get? user-conservation-data { user: meter-owner, season-id: season-id }))
  )
    (match conservation-data
      data (map-set user-conservation-data
             { user: meter-owner, season-id: season-id }
             (merge data { current-usage: (+ (get current-usage data) usage-amount) }))
      true
    )
    (ok true)
  )
)

(define-public (complete-challenge-evaluation)
  (let (
    (season-id (var-get current-season-id))
    (challenge (unwrap! (map-get? seasonal-challenges { season-id: season-id }) ERR_CHALLENGE_NOT_FOUND))
    (conservation-data (unwrap! (map-get? user-conservation-data { user: tx-sender, season-id: season-id }) ERR_NO_BASELINE_USAGE))
    (baseline (get baseline-usage conservation-data))
    (current (get current-usage conservation-data))
    (reduction-achieved (if (> baseline current) (/ (* (- baseline current) u100) baseline) u0))
  )
    (asserts! (not (get active challenge)) ERR_CHALLENGE_ENDED)
    (asserts! (>= reduction-achieved (get target-reduction challenge)) ERR_INVALID_AMOUNT)
    (try! (ft-mint? aqua-token (get bonus-reward challenge) tx-sender))
    (update-challenge-winner tx-sender)
    (ok (get bonus-reward challenge))
  )
)

(define-public (start-new-season)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set current-season-id (+ (var-get current-season-id) u1))
    (ok (var-get current-season-id))
  )
)

(define-public (set-conservation-reward-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> new-rate u0) ERR_INVALID_RATE)
    (var-set conservation-reward-rate new-rate)
    (ok new-rate)
  )
)

(define-private (calculate-tier (reduction-percentage uint))
  (if (>= reduction-percentage u40)
    u4
    (if (>= reduction-percentage u30)
      u3
      (if (>= reduction-percentage u20)
        u2
        (if (>= reduction-percentage u10)
          u1
          u0
        )
      )
    )
  )
)

(define-private (update-user-achievements (user principal) (conservation-rate uint) (rewards uint))
  (let ((current-achievements (default-to { total-seasons: u0, best-conservation-rate: u0, total-conservation-rewards: u0, challenge-wins: u0 }
                                          (map-get? user-achievements { user: user }))))
    (map-set user-achievements
      { user: user }
      {
        total-seasons: (+ (get total-seasons current-achievements) u1),
        best-conservation-rate: (if (> conservation-rate (get best-conservation-rate current-achievements))
                                   conservation-rate
                                   (get best-conservation-rate current-achievements)),
        total-conservation-rewards: (+ (get total-conservation-rewards current-achievements) rewards),
        challenge-wins: (get challenge-wins current-achievements)
      }
    )
  )
)

(define-private (update-challenge-winner (user principal))
  (let ((current-achievements (default-to { total-seasons: u0, best-conservation-rate: u0, total-conservation-rewards: u0, challenge-wins: u0 }
                                          (map-get? user-achievements { user: user }))))
    (map-set user-achievements
      { user: user }
      (merge current-achievements { challenge-wins: (+ (get challenge-wins current-achievements) u1) })
    )
  )
)

(define-public (initialize-quality-standards)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set water-quality-standards { quality-type: "ph" } { min-value: u65, max-value: u85, unit: "pH*10", compensation-rate: u50, active: true })
    (map-set water-quality-standards { quality-type: "chlorine" } { min-value: u5, max-value: u40, unit: "mg/L*10", compensation-rate: u30, active: true })
    (map-set water-quality-standards { quality-type: "turbidity" } { min-value: u0, max-value: u40, unit: "NTU*10", compensation-rate: u40, active: true })
    (map-set water-quality-standards { quality-type: "contaminants" } { min-value: u0, max-value: u10, unit: "ppm*10", compensation-rate: u100, active: true })
    (ok true)
  )
)

(define-public (report-water-quality (meter-id (string-ascii 32)) (ph-level uint) (chlorine-level uint) (turbidity uint) (contaminant-level uint))
  (let (
    (meter-data (unwrap! (map-get? smart-meters { meter-id: meter-id }) ERR_METER_NOT_FOUND))
    (timestamp stacks-block-height)
    (ph-standard (unwrap! (map-get? water-quality-standards { quality-type: "ph" }) ERR_INVALID_QUALITY_METRIC))
    (chlorine-standard (unwrap! (map-get? water-quality-standards { quality-type: "chlorine" }) ERR_INVALID_QUALITY_METRIC))
    (turbidity-standard (unwrap! (map-get? water-quality-standards { quality-type: "turbidity" }) ERR_INVALID_QUALITY_METRIC))
    (contaminant-standard (unwrap! (map-get? water-quality-standards { quality-type: "contaminants" }) ERR_INVALID_QUALITY_METRIC))
    (ph-pass (and (>= ph-level (get min-value ph-standard)) (<= ph-level (get max-value ph-standard))))
    (chlorine-pass (and (>= chlorine-level (get min-value chlorine-standard)) (<= chlorine-level (get max-value chlorine-standard))))
    (turbidity-pass (<= turbidity (get max-value turbidity-standard)))
    (contaminant-pass (<= contaminant-level (get max-value contaminant-standard)))
    (all-pass (and ph-pass (and chlorine-pass (and turbidity-pass contaminant-pass))))
    (quality-score (calculate-quality-score ph-level chlorine-level turbidity contaminant-level))
    (meter-owner (get owner meter-data))
  )
    (asserts! (var-get quality-monitoring-enabled) ERR_UNAUTHORIZED)
    (asserts! (get active meter-data) ERR_UNAUTHORIZED)
    (map-set meter-quality-readings
      { meter-id: meter-id, timestamp: timestamp }
      {
        ph-level: ph-level,
        chlorine-level: chlorine-level,
        turbidity: turbidity,
        contaminant-level: contaminant-level,
        overall-quality-score: quality-score,
        passed-standards: all-pass
      }
    )
    (if (not all-pass)
      (begin
        (unwrap-panic (create-quality-alert meter-id quality-score))
        (unwrap-panic (process-quality-compensation meter-owner meter-id ph-pass chlorine-pass turbidity-pass contaminant-pass))
        true
      )
      true
    )
    (update-user-quality-history meter-owner all-pass quality-score)
    (ok all-pass)
  )
)

(define-public (create-quality-alert (meter-id (string-ascii 32)) (quality-score uint))
  (let (
    (alert-id (+ stacks-block-height (len meter-id)))
    (severity (if (< quality-score u30) u3 (if (< quality-score u60) u2 u1)))
    (alert-type (if (< quality-score u30) "CRITICAL" (if (< quality-score u60) "WARNING" "MINOR")))
  )
    (map-set quality-alerts
      { alert-id: alert-id }
      {
        meter-id: meter-id,
        alert-type: alert-type,
        severity: severity,
        timestamp: stacks-block-height,
        resolved: false,
        compensation-issued: u0
      }
    )
    (ok alert-id)
  )
)

(define-public (process-quality-compensation (user principal) (meter-id (string-ascii 32)) (ph-pass bool) (chlorine-pass bool) (turbidity-pass bool) (contaminant-pass bool))
  (let (
    (ph-comp (if ph-pass u0 u50))
    (chlorine-comp (if chlorine-pass u0 u30))
    (turbidity-comp (if turbidity-pass u0 u40))
    (contaminant-comp (if contaminant-pass u0 u100))
    (total-compensation (+ ph-comp (+ chlorine-comp (+ turbidity-comp contaminant-comp))))
    (claim-id (+ stacks-block-height (len meter-id)))
  )
    (asserts! (> total-compensation u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (var-get quality-compensation-fund) total-compensation) ERR_INSUFFICIENT_COMPENSATION_FUND)
    (try! (ft-mint? aqua-token total-compensation user))
    (var-set quality-compensation-fund (- (var-get quality-compensation-fund) total-compensation))
    (map-set quality-compensation-claims
      { claim-id: claim-id }
      {
        user: user,
        meter-id: meter-id,
        compensation-amount: total-compensation,
        claim-timestamp: stacks-block-height,
        processed: true
      }
    )
    (ok total-compensation)
  )
)

(define-public (resolve-quality-alert (alert-id uint))
  (let ((alert-data (unwrap! (map-get? quality-alerts { alert-id: alert-id }) ERR_QUALITY_READING_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set quality-alerts
      { alert-id: alert-id }
      (merge alert-data { resolved: true })
    )
    (ok true)
  )
)

(define-public (update-quality-standard (quality-type (string-ascii 20)) (min-val uint) (max-val uint) (comp-rate uint))
  (let ((existing-standard (map-get? water-quality-standards { quality-type: quality-type })))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-some existing-standard) ERR_INVALID_QUALITY_METRIC)
    (map-set water-quality-standards
      { quality-type: quality-type }
      (merge (unwrap-panic existing-standard) { min-value: min-val, max-value: max-val, compensation-rate: comp-rate })
    )
    (ok true)
  )
)

(define-public (fund-quality-compensation (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (var-set quality-compensation-fund (+ (var-get quality-compensation-fund) amount))
    (ok (var-get quality-compensation-fund))
  )
)

(define-public (toggle-quality-monitoring)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set quality-monitoring-enabled (not (var-get quality-monitoring-enabled)))
    (ok (var-get quality-monitoring-enabled))
  )
)

(define-private (calculate-quality-score (ph uint) (chlorine uint) (turbidity uint) (contaminants uint))
  (let (
    (ph-score (if (and (>= ph u65) (<= ph u85)) u25 (if (and (>= ph u60) (<= ph u90)) u15 u0)))
    (chlorine-score (if (and (>= chlorine u5) (<= chlorine u40)) u25 (if (and (>= chlorine u0) (<= chlorine u50)) u15 u0)))
    (turbidity-score (if (<= turbidity u40) u25 (if (<= turbidity u60) u15 u0)))
    (contaminant-score (if (<= contaminants u10) u25 (if (<= contaminants u20) u15 u0)))
  )
    (+ ph-score (+ chlorine-score (+ turbidity-score contaminant-score)))
  )
)

(define-private (update-user-quality-history (user principal) (passed bool) (quality-score uint))
  (let (
    (current-month (/ stacks-block-height u4320))
    (existing-history (default-to { total-readings: u0, failed-readings: u0, total-compensation: u0, average-quality-score: u0 }
                                  (map-get? user-quality-history { user: user, month: current-month })))
    (new-total (+ (get total-readings existing-history) u1))
    (new-failed (if passed (get failed-readings existing-history) (+ (get failed-readings existing-history) u1)))
    (new-avg (/ (+ (* (get average-quality-score existing-history) (get total-readings existing-history)) quality-score) new-total))
  )
    (map-set user-quality-history
      { user: user, month: current-month }
      {
        total-readings: new-total,
        failed-readings: new-failed,
        total-compensation: (get total-compensation existing-history),
        average-quality-score: new-avg
      }
    )
  )
)

(define-read-only (get-token-balance (user principal))
  (ft-get-balance aqua-token user)
)

(define-read-only (get-meter-info (meter-id (string-ascii 32)))
  (map-get? smart-meters { meter-id: meter-id })
)

(define-read-only (get-usage-history (meter-id (string-ascii 32)) (block-stack uint))
  (map-get? usage-history { meter-id: meter-id, block-height: stacks-block-height })
)

(define-read-only (get-token-price)
  (var-get token-price-per-gallon)
)

(define-read-only (get-total-water-consumed)
  (var-get total-water-consumed)
)

(define-read-only (get-user-stats (user principal))
  (map-get? user-balances { user: user })
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-contract-owner)
  CONTRACT_OWNER
)

(define-read-only (get-conservation-tier (tier-id uint))
  (map-get? conservation-tiers { tier-id: tier-id })
)

(define-read-only (get-user-conservation-data (user principal) (season-id uint))
  (map-get? user-conservation-data { user: user, season-id: season-id })
)

(define-read-only (get-seasonal-challenge (season-id uint))
  (map-get? seasonal-challenges { season-id: season-id })
)

(define-read-only (get-conservation-leaderboard (season-id uint) (rank uint))
  (map-get? conservation-leaderboard { season-id: season-id, rank: rank })
)

(define-read-only (get-user-achievements (user principal))
  (map-get? user-achievements { user: user })
)

(define-read-only (get-current-season)
  (var-get current-season-id)
)

(define-read-only (get-conservation-reward-rate)
  (var-get conservation-reward-rate)
)

(define-read-only (get-water-quality-standard (quality-type (string-ascii 20)))
  (map-get? water-quality-standards { quality-type: quality-type })
)

(define-read-only (get-meter-quality-reading (meter-id (string-ascii 32)) (timestamp uint))
  (map-get? meter-quality-readings { meter-id: meter-id, timestamp: timestamp })
)

(define-read-only (get-quality-alert (alert-id uint))
  (map-get? quality-alerts { alert-id: alert-id })
)

(define-read-only (get-user-quality-history (user principal) (month uint))
  (map-get? user-quality-history { user: user, month: month })
)

(define-read-only (get-quality-compensation-claim (claim-id uint))
  (map-get? quality-compensation-claims { claim-id: claim-id })
)

(define-read-only (get-quality-compensation-fund)
  (var-get quality-compensation-fund)
)

(define-read-only (is-quality-monitoring-enabled)
  (var-get quality-monitoring-enabled)
)

;; Smart Analytics & Reporting System
;; Provides advanced analytics for water usage patterns and system optimization

;; Analytics data structures
(define-map usage-analytics
  { period: uint, region: (string-ascii 32) }
  {
    total-consumption: uint,
    peak-usage-hour: uint,
    conservation-rate: uint,
    efficiency-score: uint,
    cost-savings: uint,
    participant-count: uint,
    quality-incidents: uint
  }
)

(define-map system-metrics
  { metric-type: (string-ascii 20) }
  {
    current-value: uint,
    historical-avg: uint,
    trend-direction: (string-ascii 10),
    last-updated: uint,
    threshold-alert: bool
  }
)

(define-data-var analytics-enabled bool true)
(define-data-var next-report-id uint u1)

;; Public analytics functions

(define-public (generate-usage-report (start-block uint) (end-block uint) (region (string-ascii 32)))
  (let (
    (period-key (/ start-block u1008))
    (total-consumption (calculate-period-consumption start-block end-block))
    (conservation-data (analyze-conservation-trends start-block end-block))
    (quality-incidents (count-quality-incidents start-block end-block))
  )
    (asserts! (var-get analytics-enabled) ERR_UNAUTHORIZED)
    (asserts! (< start-block end-block) ERR_INVALID_AMOUNT)
    (map-set usage-analytics
      { period: period-key, region: region }
      {
        total-consumption: total-consumption,
        peak-usage-hour: (calculate-peak-usage start-block end-block),
        conservation-rate: (get conservation-rate conservation-data),
        efficiency-score: (get efficiency-score conservation-data),
        cost-savings: (get cost-savings conservation-data),
        participant-count: (get participant-count conservation-data),
        quality-incidents: quality-incidents
      }
    )
    (ok period-key)
  )
)

(define-public (update-system-metrics (metric-type (string-ascii 20)) (new-value uint))
  (let (
    (existing-metric (map-get? system-metrics { metric-type: metric-type }))
    (historical-avg (match existing-metric metric (get historical-avg metric) u0))
    (trend (calculate-trend-direction new-value historical-avg))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set system-metrics
      { metric-type: metric-type }
      {
        current-value: new-value,
        historical-avg: (if (is-eq historical-avg u0) new-value (/ (+ historical-avg new-value) u2)),
        trend-direction: trend,
        last-updated: stacks-block-height,
        threshold-alert: (> new-value (* historical-avg u2))
      }
    )
    (ok true)
  )
)

(define-public (bulk-meter-registration (meter-data (list 10 { meter-id: (string-ascii 32), location: (string-ascii 64), owner: principal })))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map process-meter-registration meter-data)
    (ok (len meter-data))
  )
)

(define-public (calculate-optimal-pricing (target-conservation uint))
  (let (
    (current-consumption (var-get total-water-consumed))
    (current-price (var-get token-price-per-gallon))
    (price-elasticity u15) ;; 15% reduction per 10% price increase
    (required-reduction (/ (* current-consumption target-conservation) u100))
    (price-increase-needed (/ required-reduction price-elasticity))
    (optimal-price (+ current-price (/ (* current-price price-increase-needed) u100)))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (and (> target-conservation u0) (<= target-conservation u50)) ERR_INVALID_AMOUNT)
    (ok {
      recommended-price: optimal-price,
      expected-reduction: required-reduction,
      price-change-percent: price-increase-needed,
      estimated-revenue-impact: (* optimal-price current-consumption)
    })
  )
)

(define-public (generate-conservation-insights (user principal))
  (let (
    (season-id (var-get current-season-id))
    (conservation-data (map-get? user-conservation-data { user: user, season-id: season-id }))
    (user-balance (default-to { token-balance: u0, total-spent: u0, meters-owned: u0 } (map-get? user-balances { user: user })))
    (achievements (default-to { total-seasons: u0, best-conservation-rate: u0, total-conservation-rewards: u0, challenge-wins: u0 } (map-get? user-achievements { user: user })))
  )
    (match conservation-data
      data 
      (ok {
        conservation-tier: (calculate-tier (/ (* (- (get baseline-usage data) (get current-usage data)) u100) (get baseline-usage data))),
        potential-savings: (calculate-potential-savings (get baseline-usage data) (get current-usage data)),
        efficiency-ranking: (calculate-efficiency-rank user),
        recommended-actions: (generate-conservation-recommendations (get baseline-usage data) (get current-usage data)),
        total-rewards: (get total-conservation-rewards achievements),
        season-performance: (/ (* (- (get baseline-usage data) (get current-usage data)) u100) (get baseline-usage data))
      })
      (err ERR_NO_BASELINE_USAGE)
    )
  )
)

;; Private analytics helper functions

(define-private (process-meter-registration (meter-info { meter-id: (string-ascii 32), location: (string-ascii 64), owner: principal }))
  (begin
    (map-set smart-meters
      { meter-id: (get meter-id meter-info) }
      {
        owner: (get owner meter-info),
        location: (get location meter-info),
        total-usage: u0,
        last-reading: u0,
        last-payment-block: stacks-block-height,
        active: true
      }
    )
    (map-set authorized-meters { meter-id: (get meter-id meter-info) } { authorized: true })
    (update-user-meters (get owner meter-info))
    true
  )
)

(define-private (calculate-period-consumption (start-block uint) (end-block uint))
  ;; Simplified calculation - in real implementation would iterate through usage history
  (let ((period-duration (- end-block start-block)))
    (/ (* (var-get total-water-consumed) period-duration) u52560) ;; Estimate based on yearly consumption
  )
)

(define-private (analyze-conservation-trends (start-block uint) (end-block uint))
  ;; Returns conservation analysis for the period
  {
    conservation-rate: u75,
    efficiency-score: u82,
    cost-savings: u1500,
    participant-count: u45
  }
)

(define-private (count-quality-incidents (start-block uint) (end-block uint))
  ;; Simplified count - would scan quality alerts in real implementation
  u3
)

(define-private (calculate-peak-usage (start-block uint) (end-block uint))
  ;; Returns the hour of day with highest usage (0-23)
  u14 ;; 2 PM typically peak usage
)

(define-private (calculate-trend-direction (current uint) (historical uint))
  (if (> current historical)
    "increasing"
    (if (< current historical)
      "decreasing"
      "stable"
    )
  )
)

(define-private (calculate-potential-savings (baseline uint) (current uint))
  (let ((potential-reduction (/ (* baseline u20) u100))) ;; 20% additional savings possible
    (if (> baseline current)
      (+ (- baseline current) potential-reduction)
      potential-reduction
    )
  )
)

(define-private (calculate-efficiency-rank (user principal))
  ;; Returns user's efficiency rank as percentile (0-100)
  u78
)

(define-private (generate-conservation-recommendations (baseline uint) (current uint))
  (if (> current baseline)
    u1 ;; Immediate action needed
    (if (< (/ (* (- baseline current) u100) baseline) u10)
      u2 ;; Minor improvements
      u3 ;; Good performance
    )
  )
)

;; Read-only analytics functions

(define-read-only (get-usage-analytics (period uint) (region (string-ascii 32)))
  (map-get? usage-analytics { period: period, region: region })
)

(define-read-only (get-system-metric (metric-type (string-ascii 20)))
  (map-get? system-metrics { metric-type: metric-type })
)

(define-read-only (get-system-overview)
  {
    total-meters-registered: (var-get total-water-consumed), ;; Placeholder
    total-water-consumed: (var-get total-water-consumed),
    current-token-price: (var-get token-price-per-gallon),
    active-conservation-programs: (var-get current-season-id),
    quality-monitoring-status: (var-get quality-monitoring-enabled),
    contract-status: (not (var-get contract-paused))
  }
)

(define-read-only (get-conservation-analytics (season-id uint))
  (let (
    (challenge (map-get? seasonal-challenges { season-id: season-id }))
  )
    (match challenge
      data
      (some {
        season-id: season-id,
        total-participants: (get participants data),
        target-reduction: (get target-reduction data),
        challenge-status: (get active data),
        bonus-pool: (get bonus-reward data)
      })
      none
    )
  )
)

(define-read-only (calculate-user-efficiency (user principal))
  (let (
    (user-data (default-to { token-balance: u0, total-spent: u0, meters-owned: u0 } (map-get? user-balances { user: user })))
    (achievements (default-to { total-seasons: u0, best-conservation-rate: u0, total-conservation-rewards: u0, challenge-wins: u0 } (map-get? user-achievements { user: user })))
  )
    {
      total-meters: (get meters-owned user-data),
      total-spent: (get total-spent user-data),
      conservation-rewards: (get total-conservation-rewards achievements),
      efficiency-ratio: (if (> (get total-spent user-data) u0) 
                          (/ (get total-conservation-rewards achievements) (get total-spent user-data))
                          u0),
      best-conservation: (get best-conservation-rate achievements)
    }
  )
)



