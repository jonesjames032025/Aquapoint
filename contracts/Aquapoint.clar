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

(define-data-var token-price-per-gallon uint u10)
(define-data-var total-water-consumed uint u0)
(define-data-var contract-paused bool false)

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