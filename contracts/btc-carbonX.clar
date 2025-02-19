;; Title: Bitcoin-Powered Carbon Credit Exchange (BTC-CarbonX) - Stacks Layer 2
;; Summary: A revolutionary carbon offset marketplace leveraging Bitcoin's security and Stacks Layer 2 scalability
;; Description: BTC-CarbonX revolutionizes carbon credit trading by combining Bitcoin's immutable ledger with 
;; Stacks Layer 2 efficiency. This smart contract enables secure, transparent, and cost-effective carbon credit 
;; transactions, featuring real-time validation, automated compliance, and seamless Bitcoin settlement. Built on 
;; Stacks L2, it offers high throughput and low fees while inheriting Bitcoin's security guarantees.

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-credit-not-available (err u105))
(define-constant err-invalid-status (err u106))
(define-constant err-transfer-failed (err u107))

;; Data Variables
(define-data-var next-credit-id uint u0)
(define-data-var next-validator-id uint u0)
(define-data-var platform-fee uint u25) ;; 2.5% fee

;; Principal Variables
(define-map credits
  { credit-id: uint }
  {
    owner: principal,
    amount: uint,
    price: uint,
    status: (string-ascii 20),
    validator: uint,
    metadata: (string-ascii 256)
  }
)

(define-map balances principal uint)

(define-map validators
  { validator-id: uint }
  {
    address: principal,
    name: (string-ascii 50),
    reputation: uint
  }
)

;; Private Functions
(define-private (transfer-stx-internal (amount uint) (sender principal) (recipient principal))
  (match (stx-transfer? amount sender recipient)
    success true
    error false
  )
)

(define-private (calculate-fee (amount uint))
  (/ (* amount (var-get platform-fee)) u1000)
)

;; Read-Only Functions
(define-read-only (get-credit (credit-id uint))
  (match (map-get? credits { credit-id: credit-id })
    credit (ok credit)
    (err err-not-found)
  )
)

(define-read-only (get-balance (user principal))
  (default-to u0 (map-get? balances user))
)

(define-read-only (get-validator (validator-id uint))
  (match (map-get? validators { validator-id: validator-id })
    validator (ok validator)
    (err err-not-found)
  )
)

;; Public Functions
(define-public (create-credit (amount uint) (price uint) (metadata (string-ascii 256)))
  (let
    (
      (credit-id (var-get next-credit-id))
      (new-credit {
        owner: tx-sender,
        amount: amount,
        price: price,
        status: "pending",
        validator: u0,
        metadata: metadata
      })
    )
    (asserts! (> amount u0) (err err-invalid-amount))
    (asserts! (> price u0) (err err-invalid-amount))
    
    (map-set credits { credit-id: credit-id } new-credit)
    (var-set next-credit-id (+ credit-id u1))
    (ok credit-id)
  )
)

(define-public (validate-credit (credit-id uint) (validator-id uint) (new-status (string-ascii 20)))
  (let
    (
      (credit (unwrap! (get-credit credit-id) (err err-not-found)))
      (validator (unwrap! (get-validator validator-id) (err err-not-found)))
    )
    (asserts! (is-eq (get address validator) tx-sender) (err err-unauthorized))
    (asserts! (is-eq (get status credit) "pending") (err err-invalid-status))
    (map-set credits { credit-id: credit-id }
      (merge credit { status: new-status, validator: validator-id })
    )
    (ok true)
  )
)

(define-public (buy-credit (credit-id uint) (amount uint))
  (let
    (
      (credit (unwrap! (get-credit credit-id) (err err-not-found)))
      (total-cost (* amount (get price credit)))
      (fee (calculate-fee total-cost))
      (seller (get owner credit))
    )
    (asserts! (is-eq (get status credit) "validated") (err err-invalid-status))
    (asserts! (<= amount (get amount credit)) (err err-credit-not-available))
    (asserts! (>= (stx-get-balance tx-sender) total-cost) (err err-insufficient-balance))
    
    (if (and 
          (transfer-stx-internal total-cost tx-sender seller)
          (transfer-stx-internal fee seller contract-owner)
        )
        (begin
          (map-set credits { credit-id: credit-id }
            (merge credit { amount: (- (get amount credit) amount) })
          )
          
          (map-set balances tx-sender
            (+ (get-balance tx-sender) amount)
          )
          
          (ok true)
        )
        (err err-transfer-failed)
    )
  )
)

(define-public (transfer-credits (recipient principal) (amount uint))
  (begin
    (asserts! (not (is-eq tx-sender recipient)) (err err-unauthorized))
    (asserts! (> amount u0) (err err-invalid-amount))
    
    (let
      (
        (sender-balance (get-balance tx-sender))
        (recipient-balance (get-balance recipient))
      )
      (asserts! (>= sender-balance amount) (err err-insufficient-balance))
      
      (map-set balances tx-sender
        (- sender-balance amount)
      )
      (map-set balances recipient
        (+ recipient-balance amount)
      )
      
      (ok true)
    )
  )
)

(define-public (retire-credits (amount uint))
  (let
    (
      (user-balance (get-balance tx-sender))
    )
    (asserts! (> amount u0) (err err-invalid-amount))
    (asserts! (>= user-balance amount) (err err-insufficient-balance))
    
    (map-set balances tx-sender
      (- user-balance amount)
    )
    
    (ok true)
  )
)


  (begin
    (asserts! (> (len name) u0) (err err-invalid-amount))
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    
    (let
      (
        (validator-id (var-get next-validator-id))
      )
      (map-set validators { validator-id: validator-id }
        {
          address: tx-sender,
          name: name,
          reputation: u100
        }
      )
      (var-set next-validator-id (+ validator-id u1))
      (ok validator-id)
    )
  )
)

(define-public (update-validator-reputation (validator-id uint) (new-reputation uint))
  (let
    (
      (validator (unwrap! (get-validator validator-id) (err err-not-found)))
    )
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (asserts! (and (>= new-reputation u0) (<= new-reputation u100)) (err err-invalid-amount))
    
    (map-set validators { validator-id: validator-id }
      (merge validator { reputation: new-reputation })
    )
    (ok true)
  )
)

(define-public (update-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) (err err-owner-only))
    (asserts! (and (>= new-fee u0) (<= new-fee u100)) (err err-invalid-amount))
    (var-set platform-fee new-fee)
    (ok true)
  )
)