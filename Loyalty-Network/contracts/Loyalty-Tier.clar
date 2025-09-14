;; Loyalty Points System Smart Contract
;; A comprehensive loyalty program with points earning, redemption, and tier management

;; ===================================
;; CONSTANTS AND ERROR CODES
;; ===================================

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-MERCHANT-NOT-FOUND (err u103))
(define-constant ERR-REWARD-NOT-FOUND (err u104))
(define-constant ERR-INSUFFICIENT-POINTS (err u105))
(define-constant ERR-EXPIRED-POINTS (err u106))
(define-constant ERR-TIER-NOT-FOUND (err u107))
(define-constant ERR-ALREADY-EXISTS (err u108))
(define-constant ERR-INVALID-PERCENTAGE (err u109))
(define-constant ERR-POINTS-EXPIRED (err u110))
(define-constant ERR-INVALID-INPUT (err u111))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant POINTS-DECIMALS u6)
(define-constant SECONDS-PER-DAY u86400)
(define-constant DAYS-PER-YEAR u365)

;; Tier thresholds
(define-constant BRONZE-THRESHOLD u0)
(define-constant SILVER-THRESHOLD u1000)
(define-constant GOLD-THRESHOLD u5000)
(define-constant PLATINUM-THRESHOLD u15000)

;; ===================================
;; DATA STRUCTURES
;; ===================================

;; User balance and tier information
(define-map user-balances
  principal
  {
    total-points: uint,
    available-points: uint,
    lifetime-earned: uint,
    lifetime-redeemed: uint,
    current-tier: (string-ascii 10),
    tier-progress: uint,
    last-activity: uint
  })

;; Points expiration tracking
(define-map points-expiry
  { user: principal, batch-id: uint }
  {
    amount: uint,
    expiry-block: uint,
    earned-block: uint
  })

;; Merchant information
(define-map merchants
  principal
  {
    name: (string-ascii 50),
    points-rate: uint, ;; points per STX spent (multiplied by POINTS-DECIMALS)
    is-active: bool,
    total-points-issued: uint
  })

;; Reward catalog
(define-map rewards
  uint
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    points-cost: uint,
    merchant: principal,
    is-active: bool,
    total-redeemed: uint,
    tier-requirement: (string-ascii 10)
  })

;; Transaction history
(define-map transaction-history
  uint
  {
    user: principal,
    transaction-type: (string-ascii 20), ;; "earn", "redeem", "expire", "transfer"
    amount: uint,
    merchant: (optional principal),
    reward-id: (optional uint),
    timestamp: uint,
    block-height: uint
  })

;; ===================================
;; DATA VARIABLES
;; ===================================

(define-data-var next-reward-id uint u1)
(define-data-var next-transaction-id uint u1)
(define-data-var next-batch-id uint u1)
(define-data-var points-expiry-days uint u365) ;; Points expire after 1 year
(define-data-var contract-paused bool false)

;; ===================================
;; PRIVATE FUNCTIONS
;; ===================================

;; Check if caller is contract owner
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER))

;; Get current block height
(define-private (get-current-block)
  stacks-block-height)

;; Validate merchant name
(define-private (is-valid-name (name (string-ascii 50)))
  (and (> (len name) u0) (<= (len name) u50)))

;; Validate reward name
(define-private (is-valid-reward-name (name (string-ascii 100)))
  (and (> (len name) u0) (<= (len name) u100)))

;; Validate reward description
(define-private (is-valid-description (description (string-ascii 500)))
  (<= (len description) u500))

;; Validate tier requirement
(define-private (is-valid-tier (tier (string-ascii 10)))
  (or (is-eq tier "BRONZE")
      (is-eq tier "SILVER")
      (is-eq tier "GOLD")
      (is-eq tier "PLATINUM")))

;; Validate principal (basic check - not zero address)
(define-private (is-valid-principal (user principal))
  (not (is-eq user 'SP000000000000000000002Q6VF78)))

;; Validate batch-id (must be greater than 0)
(define-private (is-valid-batch-id (batch-id uint))
  (> batch-id u0))

;; Calculate tier based on lifetime points
(define-private (calculate-tier (lifetime-points uint))
  (if (>= lifetime-points PLATINUM-THRESHOLD)
    "PLATINUM"
    (if (>= lifetime-points GOLD-THRESHOLD)
      "GOLD"
      (if (>= lifetime-points SILVER-THRESHOLD)
        "SILVER"
        "BRONZE"))))

;; Calculate tier progress percentage
(define-private (calculate-tier-progress (lifetime-points uint))
  (let ((current-tier (calculate-tier lifetime-points)))
    (if (is-eq current-tier "PLATINUM")
      u100
      (if (is-eq current-tier "GOLD")
        (/ (* (- lifetime-points GOLD-THRESHOLD) u100) (- PLATINUM-THRESHOLD GOLD-THRESHOLD))
        (if (is-eq current-tier "SILVER")
          (/ (* (- lifetime-points SILVER-THRESHOLD) u100) (- GOLD-THRESHOLD SILVER-THRESHOLD))
          (/ (* lifetime-points u100) SILVER-THRESHOLD))))))

;; Get tier multiplier for points earning
(define-private (get-tier-multiplier (tier (string-ascii 10)))
  (if (is-eq tier "PLATINUM")
    u150 ;; 1.5x multiplier
    (if (is-eq tier "GOLD")
      u125 ;; 1.25x multiplier
      (if (is-eq tier "SILVER")
        u110 ;; 1.1x multiplier
        u100)))) ;; 1x multiplier for bronze

;; Check if points have expired
(define-private (is-points-expired (expiry-block uint))
  (> (get-current-block) expiry-block))

;; Record transaction in history (simplified to never fail)
(define-private (record-transaction
  (user principal)
  (tx-type (string-ascii 20))
  (amount uint)
  (merchant (optional principal))
  (reward-id (optional uint)))
  (let ((tx-id (var-get next-transaction-id))
        (current-time (default-to u0 (get-stacks-block-info? time (get-current-block)))))
    (begin
      (map-set transaction-history tx-id
        {
          user: user,
          transaction-type: tx-type,
          amount: amount,
          merchant: merchant,
          reward-id: reward-id,
          timestamp: current-time,
          block-height: (get-current-block)
        })
      (var-set next-transaction-id (+ tx-id u1))
      tx-id)))

;; Update user balance and tier
(define-private (update-user-balance
  (user principal)
  (total-delta int)
  (available-delta int)
  (earned-delta uint)
  (redeemed-delta uint))
  (let ((current-balance (default-to
          {
            total-points: u0,
            available-points: u0,
            lifetime-earned: u0,
            lifetime-redeemed: u0,
            current-tier: "BRONZE",
            tier-progress: u0,
            last-activity: (get-current-block)
          }
          (map-get? user-balances user))))
    (let ((new-total (if (< total-delta 0)
                       (if (>= (get total-points current-balance) (to-uint (- 0 total-delta)))
                         (- (get total-points current-balance) (to-uint (- 0 total-delta)))
                         u0)
                       (+ (get total-points current-balance) (to-uint total-delta))))
          (new-available (if (< available-delta 0)
                          (if (>= (get available-points current-balance) (to-uint (- 0 available-delta)))
                            (- (get available-points current-balance) (to-uint (- 0 available-delta)))
                            u0)
                          (+ (get available-points current-balance) (to-uint available-delta))))
          (new-lifetime-earned (+ (get lifetime-earned current-balance) earned-delta))
          (new-lifetime-redeemed (+ (get lifetime-redeemed current-balance) redeemed-delta))
          (new-tier (calculate-tier new-lifetime-earned))
          (new-tier-progress (calculate-tier-progress new-lifetime-earned)))
      ;; Validate that we're not creating negative balances
      (asserts! (>= new-available u0) ERR-INSUFFICIENT-BALANCE)
      (asserts! (>= new-total u0) ERR-INSUFFICIENT-BALANCE)
      (map-set user-balances user
        {
          total-points: new-total,
          available-points: new-available,
          lifetime-earned: new-lifetime-earned,
          lifetime-redeemed: new-lifetime-redeemed,
          current-tier: new-tier,
          tier-progress: new-tier-progress,
          last-activity: (get-current-block)
        })
      (ok true))))

;; ===================================
;; PUBLIC FUNCTIONS - ADMIN
;; ===================================

;; Register a new merchant
(define-public (register-merchant (merchant principal) (name (string-ascii 50)) (points-rate uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? merchants merchant)) ERR-ALREADY-EXISTS)
    (asserts! (> points-rate u0) ERR-INVALID-AMOUNT)
    ;; Input validation
    (asserts! (is-valid-principal merchant) ERR-INVALID-INPUT)
    (asserts! (is-valid-name name) ERR-INVALID-INPUT)
    (map-set merchants merchant
      {
        name: name,
        points-rate: points-rate,
        is-active: true,
        total-points-issued: u0
      })
    (ok true)))

;; Update merchant status
(define-public (update-merchant-status (merchant principal) (is-active bool))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-some (map-get? merchants merchant)) ERR-MERCHANT-NOT-FOUND)
    (map-set merchants merchant
      (merge (unwrap-panic (map-get? merchants merchant))
             { is-active: is-active }))
    (ok true)))

;; Add reward to catalog
(define-public (add-reward
  (name (string-ascii 100))
  (description (string-ascii 500))
  (points-cost uint)
  (merchant principal)
  (tier-requirement (string-ascii 10)))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (> points-cost u0) ERR-INVALID-AMOUNT)
    (asserts! (is-some (map-get? merchants merchant)) ERR-MERCHANT-NOT-FOUND)
    ;; Input validation
    (asserts! (is-valid-reward-name name) ERR-INVALID-INPUT)
    (asserts! (is-valid-description description) ERR-INVALID-INPUT)
    (asserts! (is-valid-tier tier-requirement) ERR-INVALID-INPUT)
    (let ((reward-id (var-get next-reward-id)))
      (map-set rewards reward-id
        {
          name: name,
          description: description,
          points-cost: points-cost,
          merchant: merchant,
          is-active: true,
          total-redeemed: u0,
          tier-requirement: tier-requirement
        })
      (var-set next-reward-id (+ reward-id u1))
      (ok reward-id))))

;; Update reward status
(define-public (update-reward-status (reward-id uint) (is-active bool))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (is-some (map-get? rewards reward-id)) ERR-REWARD-NOT-FOUND)
    (map-set rewards reward-id
      (merge (unwrap-panic (map-get? rewards reward-id))
             { is-active: is-active }))
    (ok true)))

;; Set points expiry period
(define-public (set-points-expiry-days (days uint))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (asserts! (> days u0) ERR-INVALID-AMOUNT)
    (var-set points-expiry-days days)
    (ok true)))

;; Pause/unpause contract
(define-public (set-contract-pause (paused bool))
  (begin
    (asserts! (is-contract-owner) ERR-UNAUTHORIZED)
    (var-set contract-paused paused)
    (ok true)))

;; ===================================
;; PUBLIC FUNCTIONS - USER ACTIONS
;; ===================================

;; Earn points from purchase
(define-public (earn-points (user principal) (stx-amount uint))
  (let ((merchant-info (unwrap! (map-get? merchants tx-sender) ERR-MERCHANT-NOT-FOUND)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
      (asserts! (get is-active merchant-info) ERR-UNAUTHORIZED)
      (asserts! (> stx-amount u0) ERR-INVALID-AMOUNT)
      ;; Input validation
      (asserts! (is-valid-principal user) ERR-INVALID-INPUT)
      
      ;; Calculate base points
      (let ((base-points (/ (* stx-amount (get points-rate merchant-info)) (pow u10 POINTS-DECIMALS)))
            (user-balance (map-get? user-balances user))
            (current-tier (if (is-some user-balance)
                            (get current-tier (unwrap-panic user-balance))
                            "BRONZE"))
            (tier-multiplier (get-tier-multiplier current-tier))
            (final-points (/ (* base-points tier-multiplier) u100))
            (batch-id (var-get next-batch-id))
            (expiry-block (+ (get-current-block) (* (var-get points-expiry-days) SECONDS-PER-DAY))))
        
        ;; Update user balance
        (try! (update-user-balance user (to-int final-points) (to-int final-points) final-points u0))
        
        ;; Record points expiry
        (map-set points-expiry
          { user: user, batch-id: batch-id }
          {
            amount: final-points,
            expiry-block: expiry-block,
            earned-block: (get-current-block)
          })
        
        ;; Update merchant stats
        (map-set merchants tx-sender
          (merge merchant-info
                 { total-points-issued: (+ (get total-points-issued merchant-info) final-points) }))
        
        ;; Record transaction and increment batch ID
        (begin
          (record-transaction user "earn" final-points (some tx-sender) none)
          (var-set next-batch-id (+ batch-id u1))
          (ok final-points))))))

;; Redeem points for reward
(define-public (redeem-reward (reward-id uint))
  (let ((reward-info (unwrap! (map-get? rewards reward-id) ERR-REWARD-NOT-FOUND))
        (user-balance (unwrap! (map-get? user-balances tx-sender) ERR-INSUFFICIENT-BALANCE)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
      (asserts! (get is-active reward-info) ERR-REWARD-NOT-FOUND)
      (asserts! (>= (get available-points user-balance) (get points-cost reward-info)) ERR-INSUFFICIENT-POINTS)
      
      ;; Check tier requirement
      (let ((required-tier (get tier-requirement reward-info))
            (user-tier (get current-tier user-balance))
            (points-to-deduct (get points-cost reward-info)))
        (asserts! (or (is-eq required-tier "BRONZE")
                      (and (is-eq required-tier "SILVER") 
                           (or (is-eq user-tier "SILVER") (is-eq user-tier "GOLD") (is-eq user-tier "PLATINUM")))
                      (and (is-eq required-tier "GOLD")
                           (or (is-eq user-tier "GOLD") (is-eq user-tier "PLATINUM")))
                      (and (is-eq required-tier "PLATINUM")
                           (is-eq user-tier "PLATINUM"))) ERR-TIER-NOT-FOUND)
        
        ;; Update user balance (subtract points)
        (try! (update-user-balance tx-sender 
                                  (- 0 (to-int points-to-deduct))
                                  (- 0 (to-int points-to-deduct))
                                  u0 
                                  points-to-deduct))
        
        ;; Update reward stats
        (map-set rewards reward-id
          (merge reward-info
                 { total-redeemed: (+ (get total-redeemed reward-info) u1) }))
        
        ;; Record transaction
        (begin
          (record-transaction tx-sender "redeem" points-to-deduct (some (get merchant reward-info)) (some reward-id))
          (ok true))))))

;; Transfer points between users
(define-public (transfer-points (recipient principal) (amount uint))
  (let ((sender-balance (unwrap! (map-get? user-balances tx-sender) ERR-INSUFFICIENT-BALANCE)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
      (asserts! (> amount u0) ERR-INVALID-AMOUNT)
      (asserts! (>= (get available-points sender-balance) amount) ERR-INSUFFICIENT-POINTS)
      (asserts! (not (is-eq tx-sender recipient)) ERR-UNAUTHORIZED)
      ;; Input validation
      (asserts! (is-valid-principal recipient) ERR-INVALID-INPUT)
      
      ;; Update sender balance (subtract points)
      (try! (update-user-balance tx-sender (- 0 (to-int amount)) (- 0 (to-int amount)) u0 u0))
      
      ;; Update recipient balance (add points)
      (try! (update-user-balance recipient (to-int amount) (to-int amount) u0 u0))
      
      ;; Record transactions
      (begin
        (record-transaction tx-sender "transfer-out" amount none none)
        (record-transaction recipient "transfer-in" amount none none)
        (ok true)))))

;; Clean up expired points
(define-public (cleanup-expired-points (user principal) (batch-id uint))
  (begin
    ;; Input validation first
    (asserts! (is-valid-principal user) ERR-INVALID-INPUT)
    (asserts! (is-valid-batch-id batch-id) ERR-INVALID-INPUT)
    
    (let ((points-batch (unwrap! (map-get? points-expiry { user: user, batch-id: batch-id }) ERR-POINTS-EXPIRED)))
      (begin
        (asserts! (is-points-expired (get expiry-block points-batch)) ERR-POINTS-EXPIRED)
        
        (let ((expired-amount (get amount points-batch)))
          ;; Remove expired points from user balance
          (try! (update-user-balance user 
                                    (- 0 (to-int expired-amount))
                                    (- 0 (to-int expired-amount))
                                    u0 
                                    u0))
          
          ;; Remove expiry record
          (map-delete points-expiry { user: user, batch-id: batch-id })
          
          ;; Record transaction
          (begin
            (record-transaction user "expire" expired-amount none none)
            (ok expired-amount)))))))

;; ===================================
;; READ-ONLY FUNCTIONS
;; ===================================

;; Get user balance and information
(define-read-only (get-user-balance (user principal))
  (map-get? user-balances user))

;; Get merchant information
(define-read-only (get-merchant-info (merchant principal))
  (map-get? merchants merchant))

;; Get reward information
(define-read-only (get-reward-info (reward-id uint))
  (map-get? rewards reward-id))

;; Get transaction history
(define-read-only (get-transaction (tx-id uint))
  (map-get? transaction-history tx-id))

;; Get points expiry information
(define-read-only (get-points-expiry (user principal) (batch-id uint))
  (map-get? points-expiry { user: user, batch-id: batch-id }))

;; Get contract configuration
(define-read-only (get-contract-config)
  {
    points-expiry-days: (var-get points-expiry-days),
    contract-paused: (var-get contract-paused),
    next-reward-id: (var-get next-reward-id),
    next-transaction-id: (var-get next-transaction-id),
    contract-owner: CONTRACT-OWNER
  })

;; Check if user meets tier requirement for reward
(define-read-only (can-redeem-reward (user principal) (reward-id uint))
  (match (map-get? user-balances user)
    user-balance
    (match (map-get? rewards reward-id)
      reward-info
      (let ((user-tier (get current-tier user-balance))
            (required-tier (get tier-requirement reward-info))
            (has-points (>= (get available-points user-balance) (get points-cost reward-info))))
        {
          has-sufficient-points: has-points,
          meets-tier-requirement: (or (is-eq required-tier "BRONZE")
                                     (and (is-eq required-tier "SILVER") 
                                          (or (is-eq user-tier "SILVER") (is-eq user-tier "GOLD") (is-eq user-tier "PLATINUM")))
                                     (and (is-eq required-tier "GOLD")
                                          (or (is-eq user-tier "GOLD") (is-eq user-tier "PLATINUM")))
                                     (and (is-eq required-tier "PLATINUM")
                                          (is-eq user-tier "PLATINUM"))),
          can-redeem: (and has-points
                          (or (is-eq required-tier "BRONZE")
                              (and (is-eq required-tier "SILVER") 
                                   (or (is-eq user-tier "SILVER") (is-eq user-tier "GOLD") (is-eq user-tier "PLATINUM")))
                              (and (is-eq required-tier "GOLD")
                                   (or (is-eq user-tier "GOLD") (is-eq user-tier "PLATINUM")))
                              (and (is-eq required-tier "PLATINUM")
                                   (is-eq user-tier "PLATINUM"))))
        })
      { has-sufficient-points: false, meets-tier-requirement: false, can-redeem: false })
    { has-sufficient-points: false, meets-tier-requirement: false, can-redeem: false }))

;; Get tier requirements
(define-read-only (get-tier-requirements)
  {
    bronze-threshold: BRONZE-THRESHOLD,
    silver-threshold: SILVER-THRESHOLD,
    gold-threshold: GOLD-THRESHOLD,
    platinum-threshold: PLATINUM-THRESHOLD
  })