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

(define-data-var token-price-per-gallon uint u10)
(define-data-var total-water-consumed uint u0)
(define-data-var contract-paused bool false)
(define-data-var current-season-id uint u1)
(define-data-var conservation-reward-rate uint u5)

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