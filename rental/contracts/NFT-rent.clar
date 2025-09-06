;; NFT Rental Contract
;; A robust smart contract for renting NFTs with comprehensive features

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INVALID_PARAMS (err u400))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_RENTAL_EXPIRED (err u410))
(define-constant ERR_RENTAL_ACTIVE (err u411))
(define-constant ERR_NFT_NOT_AVAILABLE (err u412))
(define-constant ERR_INVALID_CONTRACT (err u413))

;; Data Variables
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var min-rental-duration uint u1440) ;; 24 hours in blocks
(define-data-var max-rental-duration uint u144000) ;; ~100 days in blocks

;; Approved NFT contracts map for security
(define-map approved-contracts principal bool)

;; Data Maps
(define-map rentals
  { nft-contract: principal, token-id: uint }
  {
    owner: principal,
    renter: (optional principal),
    price-per-block: uint,
    start-block: uint,
    end-block: uint,
    collateral: uint,
    is-active: bool
  }
)

(define-map rental-earnings principal uint)
(define-map user-ratings 
  principal 
  { total-score: uint, rating-count: uint }
)

;; Private Functions
(define-private (is-contract-approved (contract-principal principal))
  (default-to false (map-get? approved-contracts contract-principal))
)

(define-private (is-rental-expired (nft-contract principal) (token-id uint))
  (match (map-get? rentals { nft-contract: nft-contract, token-id: token-id })
    rental (>= block-height (get end-block rental))
    false
  )
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Read-only Functions
(define-read-only (get-rental-info (nft-contract principal) (token-id uint))
  (map-get? rentals { nft-contract: nft-contract, token-id: token-id })
)

(define-read-only (get-user-earnings (user principal))
  (default-to u0 (map-get? rental-earnings user))
)

(define-read-only (get-user-rating (user principal))
  (match (map-get? user-ratings user)
    rating-data 
      (if (> (get rating-count rating-data) u0)
        (some (/ (get total-score rating-data) (get rating-count rating-data)))
        none
      )
    none
  )
)

(define-read-only (is-nft-available (nft-contract principal) (token-id uint))
  (match (map-get? rentals { nft-contract: nft-contract, token-id: token-id })
    rental 
      (or 
        (not (get is-active rental))
        (>= block-height (get end-block rental))
      )
    true
  )
)

(define-read-only (calculate-rental-cost (price-per-block uint) (duration uint))
  (let ((total-cost (* price-per-block duration))
        (platform-fee (calculate-platform-fee total-cost)))
    { 
      rental-cost: total-cost,
      platform-fee: platform-fee,
      total-cost: (+ total-cost platform-fee)
    }
  )
)

(define-read-only (is-approved-contract (contract-principal principal))
  (is-contract-approved contract-principal)
)

;; Admin Functions
(define-public (approve-nft-contract (contract-principal principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set approved-contracts contract-principal true)
    (print { event: "contract-approved", contract: contract-principal })
    (ok true)
  )
)

(define-public (revoke-nft-contract (contract-principal principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-delete approved-contracts contract-principal)
    (print { event: "contract-revoked", contract: contract-principal })
    (ok true)
  )
)

;; Safe NFT Operations using direct STX transfers for escrow
(define-public (list-nft-for-rent 
  (nft-contract principal) 
  (token-id uint) 
  (price-per-block uint) 
  (collateral uint))
  (let ((rental-key { nft-contract: nft-contract, token-id: token-id }))
    (asserts! (is-contract-approved nft-contract) ERR_INVALID_CONTRACT)
    (asserts! (> price-per-block u0) ERR_INVALID_PARAMS)
    (asserts! (> collateral u0) ERR_INVALID_PARAMS)
    (asserts! (is-nft-available nft-contract token-id) ERR_NFT_NOT_AVAILABLE)
    
    ;; Create rental listing (NFT stays with owner until rented)
    (map-set rentals rental-key {
      owner: tx-sender,
      renter: none,
      price-per-block: price-per-block,
      start-block: u0,
      end-block: u0,
      collateral: collateral,
      is-active: false
    })
    
    (print { 
      event: "nft-listed", 
      nft-contract: nft-contract, 
      token-id: token-id, 
      owner: tx-sender,
      price-per-block: price-per-block,
      collateral: collateral
    })
    (ok true)
  )
)

(define-public (rent-nft 
  (nft-contract principal) 
  (token-id uint) 
  (duration uint))
  (let (
    (rental-key { nft-contract: nft-contract, token-id: token-id })
    (rental-info (unwrap! (map-get? rentals rental-key) ERR_NOT_FOUND))
    (cost-info (calculate-rental-cost (get price-per-block rental-info) duration))
    (total-payment (+ (get total-cost cost-info) (get collateral rental-info)))
  )
    (asserts! (is-contract-approved nft-contract) ERR_INVALID_CONTRACT)
    (asserts! (>= duration (var-get min-rental-duration)) ERR_INVALID_PARAMS)
    (asserts! (<= duration (var-get max-rental-duration)) ERR_INVALID_PARAMS)
    (asserts! (not (get is-active rental-info)) ERR_RENTAL_ACTIVE)
    (asserts! (>= (stx-get-balance tx-sender) total-payment) ERR_INSUFFICIENT_FUNDS)
    (asserts! (not (is-eq tx-sender (get owner rental-info))) ERR_INVALID_PARAMS)
    
    ;; Transfer total payment to contract as escrow
    (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
    
    ;; Transfer rental cost to owner
    (try! (as-contract (stx-transfer? (get rental-cost cost-info) tx-sender (get owner rental-info))))
    
    ;; Transfer platform fee to contract owner
    (try! (as-contract (stx-transfer? (get platform-fee cost-info) tx-sender CONTRACT_OWNER)))
    
    ;; Update rental info
    (map-set rentals rental-key (merge rental-info {
      renter: (some tx-sender),
      start-block: block-height,
      end-block: (+ block-height duration),
      is-active: true
    }))
    
    ;; Update owner earnings
    (map-set rental-earnings 
      (get owner rental-info)
      (+ (get-user-earnings (get owner rental-info)) (get rental-cost cost-info))
    )
    
    (print { 
      event: "nft-rented", 
      nft-contract: nft-contract, 
      token-id: token-id, 
      renter: tx-sender,
      duration: duration,
      cost: (get total-cost cost-info)
    })
    (ok true)
  )
)

(define-public (end-rental (nft-contract principal) (token-id uint))
  (let (
    (rental-key { nft-contract: nft-contract, token-id: token-id })
    (rental-info (unwrap! (map-get? rentals rental-key) ERR_NOT_FOUND))
    (renter (unwrap! (get renter rental-info) ERR_NOT_FOUND))
  )
    (asserts! (or 
      (is-eq tx-sender renter)
      (is-eq tx-sender (get owner rental-info))
    ) ERR_UNAUTHORIZED)
    (asserts! (get is-active rental-info) ERR_NOT_FOUND)
    
    ;; Return collateral to renter if returned on time, otherwise to owner
    (let ((collateral-recipient 
      (if (< block-height (get end-block rental-info))
        renter
        (get owner rental-info)
      )))
      (try! (as-contract (stx-transfer? (get collateral rental-info) tx-sender collateral-recipient)))
    )
    
    ;; Update rental status
    (map-set rentals rental-key (merge rental-info {
      is-active: false,
      renter: none
    }))
    
    (print { 
      event: "rental-ended", 
      nft-contract: nft-contract, 
      token-id: token-id, 
      ended-by: tx-sender
    })
    (ok true)
  )
)

(define-public (unlist-nft (nft-contract principal) (token-id uint))
  (let (
    (rental-key { nft-contract: nft-contract, token-id: token-id })
    (rental-info (unwrap! (map-get? rentals rental-key) ERR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender (get owner rental-info)) ERR_UNAUTHORIZED)
    (asserts! (not (get is-active rental-info)) ERR_RENTAL_ACTIVE)
    
    ;; Remove rental listing
    (map-delete rentals rental-key)
    
    (print { 
      event: "nft-unlisted", 
      nft-contract: nft-contract, 
      token-id: token-id, 
      owner: tx-sender
    })
    (ok true)
  )
)

(define-public (rate-user (user principal) (rating uint))
  (begin
    (asserts! (<= rating u5) ERR_INVALID_PARAMS)
    (asserts! (>= rating u1) ERR_INVALID_PARAMS)
    (asserts! (not (is-eq tx-sender user)) ERR_INVALID_PARAMS)
    
    (match (map-get? user-ratings user)
      existing-rating
        (map-set user-ratings user {
          total-score: (+ (get total-score existing-rating) rating),
          rating-count: (+ (get rating-count existing-rating) u1)
        })
      (map-set user-ratings user {
        total-score: rating,
        rating-count: u1
      })
    )
    
    (print { event: "user-rated", user: user, rating: rating, rater: tx-sender })
    (ok true)
  )
)

(define-public (extend-rental 
  (nft-contract principal) 
  (token-id uint) 
  (additional-duration uint))
  (let (
    (rental-key { nft-contract: nft-contract, token-id: token-id })
    (rental-info (unwrap! (map-get? rentals rental-key) ERR_NOT_FOUND))
    (renter (unwrap! (get renter rental-info) ERR_NOT_FOUND))
    (cost-info (calculate-rental-cost (get price-per-block rental-info) additional-duration))
  )
    (asserts! (is-contract-approved nft-contract) ERR_INVALID_CONTRACT)
    (asserts! (is-eq tx-sender renter) ERR_UNAUTHORIZED)
    (asserts! (get is-active rental-info) ERR_NOT_FOUND)
    (asserts! (< block-height (get end-block rental-info)) ERR_RENTAL_EXPIRED)
    (asserts! (>= (stx-get-balance tx-sender) (get total-cost cost-info)) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer payment to contract
    (try! (stx-transfer? (get total-cost cost-info) tx-sender (as-contract tx-sender)))
    
    ;; Transfer rental cost to owner
    (try! (as-contract (stx-transfer? (get rental-cost cost-info) tx-sender (get owner rental-info))))
    
    ;; Transfer platform fee to contract owner
    (try! (as-contract (stx-transfer? (get platform-fee cost-info) tx-sender CONTRACT_OWNER)))
    
    ;; Extend rental period
    (map-set rentals rental-key (merge rental-info {
      end-block: (+ (get end-block rental-info) additional-duration)
    }))
    
    ;; Update owner earnings
    (map-set rental-earnings 
      (get owner rental-info)
      (+ (get-user-earnings (get owner rental-info)) (get rental-cost cost-info))
    )
    
    (print { 
      event: "rental-extended", 
      nft-contract: nft-contract, 
      token-id: token-id, 
      additional-duration: additional-duration
    })
    (ok true)
  )
)

(define-public (update-rental-price 
  (nft-contract principal) 
  (token-id uint) 
  (new-price-per-block uint))
  (let ((rental-key { nft-contract: nft-contract, token-id: token-id })
        (rental-info (unwrap! (map-get? rentals rental-key) ERR_NOT_FOUND)))
    (asserts! (is-contract-approved nft-contract) ERR_INVALID_CONTRACT)
    (asserts! (is-eq tx-sender (get owner rental-info)) ERR_UNAUTHORIZED)
    (asserts! (not (get is-active rental-info)) ERR_RENTAL_ACTIVE)
    (asserts! (> new-price-per-block u0) ERR_INVALID_PARAMS)
    
    (map-set rentals rental-key (merge rental-info {
      price-per-block: new-price-per-block
    }))
    
    (print { 
      event: "rental-price-updated", 
      nft-contract: nft-contract, 
      token-id: token-id,
      new-price: new-price-per-block
    })
    (ok true)
  )
)

;; Admin Functions
(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_PARAMS) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (print { event: "platform-fee-updated", new-rate: new-rate })
    (ok true)
  )
)

(define-public (set-rental-duration-limits (min-duration uint) (max-duration uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (< min-duration max-duration) ERR_INVALID_PARAMS)
    (var-set min-rental-duration min-duration)
    (var-set max-rental-duration max-duration)
    (print { event: "duration-limits-updated", min: min-duration, max: max-duration })
    (ok true)
  )
)

(define-public (emergency-refund (nft-contract principal) (token-id uint))
  (let (
    (rental-key { nft-contract: nft-contract, token-id: token-id })
    (rental-info (unwrap! (map-get? rentals rental-key) ERR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-contract-approved nft-contract) ERR_INVALID_CONTRACT)
    
    ;; Return collateral if rental was active
    (if (get is-active rental-info)
      (match (get renter rental-info)
        renter-principal
          (try! (as-contract (stx-transfer? (get collateral rental-info) tx-sender renter-principal)))
        true
      )
      true
    )
    
    ;; Update rental status
    (map-set rentals rental-key (merge rental-info {
      is-active: false,
      renter: none
    }))
    
    (print { event: "emergency-refund", nft-contract: nft-contract, token-id: token-id })
    (ok true)
  )
)

;; Utility Functions
(define-read-only (get-platform-fee-rate)
  (var-get platform-fee-rate)
)

(define-read-only (get-rental-duration-limits)
  {
    min-duration: (var-get min-rental-duration),
    max-duration: (var-get max-rental-duration)
  }
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-rental-status (nft-contract principal) (token-id uint))
  (let ((rental-info (map-get? rentals { nft-contract: nft-contract, token-id: token-id })))
    (match rental-info
      rental
        {
          exists: true,
          is-active: (get is-active rental),
          is-expired: (>= block-height (get end-block rental)),
          owner: (get owner rental),
          renter: (get renter rental),
          end-block: (get end-block rental),
          blocks-remaining: (if (and (get is-active rental) (< block-height (get end-block rental)))
            (- (get end-block rental) block-height)
            u0
          )
        }
      { 
        exists: false, 
        is-active: false, 
        is-expired: false, 
        owner: tx-sender, 
        renter: none, 
        end-block: u0,
        blocks-remaining: u0
      }
    )
  )
)

;; Dispute resolution
(define-public (resolve-dispute 
  (nft-contract principal) 
  (token-id uint) 
  (refund-to-renter bool))
  (let (
    (rental-key { nft-contract: nft-contract, token-id: token-id })
    (rental-info (unwrap! (map-get? rentals rental-key) ERR_NOT_FOUND))
    (renter (unwrap! (get renter rental-info) ERR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-contract-approved nft-contract) ERR_INVALID_CONTRACT)
    (asserts! (get is-active rental-info) ERR_NOT_FOUND)
    
    ;; Handle collateral based on dispute resolution
    (if refund-to-renter
      (try! (as-contract (stx-transfer? (get collateral rental-info) tx-sender renter)))
      (try! (as-contract (stx-transfer? (get collateral rental-info) tx-sender (get owner rental-info))))
    )
    
    ;; End rental
    (map-set rentals rental-key (merge rental-info {
      is-active: false,
      renter: none
    }))
    
    (print { 
      event: "dispute-resolved", 
      nft-contract: nft-contract, 
      token-id: token-id,
      refund-to-renter: refund-to-renter
    })
    (ok true)
  )
)

;; Batch operations for efficiency
(define-public (batch-unlist (listings (list 10 { nft-contract: principal, token-id: uint })))
  (begin
    (asserts! (> (len listings) u0) ERR_INVALID_PARAMS)
    (fold process-unlist-item listings (ok u0))
  )
)

(define-private (process-unlist-item 
  (item { nft-contract: principal, token-id: uint })
  (previous-result (response uint uint)))
  (match previous-result
    ok-value 
      (match (unlist-nft (get nft-contract item) (get token-id item))
        success (ok (+ ok-value u1))
        error (err error)
      )
    err-value (err err-value)
  )
)

;; Initialize approved contracts (must be called by admin)
(map-set approved-contracts CONTRACT_OWNER true)