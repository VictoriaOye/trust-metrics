;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_USER_NOT_FOUND (err u404))
(define-constant ERR_INVALID_INPUT (err u400))
(define-constant ERR_ALREADY_REVIEWED (err u403))
(define-constant ERR_SELF_REVIEW (err u405))
(define-constant ERR_INSUFFICIENT_STAKE (err u402))
(define-constant ERR_DOMAIN_NOT_FOUND (err u406))
(define-constant MIN_STAKE_AMOUNT u1000)
(define-constant MAX_RATING u100)
(define-constant REPUTATION_DECAY_RATE u2) ;; 2% decay per period

;; Data structures
(define-map user-profiles
  { user: principal }
  {
    overall-score: uint,
    total-reviews-received: uint,
    total-reviews-given: uint,
    stake-amount: uint,
    joined-at: uint,
    last-activity: uint,
    is-verified: bool,
    reputation-tier: uint
  }
)

(define-map domain-scores
  { user: principal, domain: (string-ascii 20) }
  {
    score: uint,
    reviews-count: uint,
    weighted-average: uint,
    last-updated: uint,
    expertise-level: uint
  }
)

(define-map review-records
  { reviewer: principal, reviewee: principal, domain: (string-ascii 20) }
  {
    rating: uint,
    weight: uint,
    comment-hash: (buff 32),
    created-at: uint,
    is-disputed: bool,
    stake-locked: uint
  }
)

(define-map reputation-domains
  { domain: (string-ascii 20) }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    total-participants: uint,
    average-score: uint,
    is-active: bool,
    created-at: uint
  }
)

(define-map attestations
  { attester: principal, user: principal, attestation-type: (string-ascii 30) }
  {
    value: uint,
    confidence: uint,
    created-at: uint,
    expires-at: (optional uint),
    is-verified: bool
  }
)

(define-map reputation-history
  { user: principal, period: uint }
  {
    score-snapshot: uint,
    activity-count: uint,
    decay-applied: uint,
    period-start: uint
  }
)

;; Data variables
(define-data-var total-users uint u0)
(define-data-var total-reviews uint u0)
(define-data-var total-domains uint u0)
(define-data-var reputation-period uint u0)
(define-data-var global-average-score uint u50)

;; Helper functions
(define-private (validate-string-input (input (string-ascii 50)))
  (> (len input) u0)
)

(define-private (validate-rating (rating uint))
  (and (> rating u0) (<= rating MAX_RATING))
)

(define-private (calculate-review-weight (reviewer-score uint) (stake-amount uint))
  (let ((base-weight (/ reviewer-score u10)))
    (+ base-weight (/ stake-amount u100))
  )
)

(define-private (calculate-weighted-score (current-score uint) (current-count uint) (new-rating uint) (weight uint))
  (if (is-eq current-count u0)
    new-rating
    (/ (+ (* current-score current-count) (* new-rating weight)) (+ current-count weight))
  )
)

(define-private (apply-reputation-decay (current-score uint))
  (let ((decay-amount (/ (* current-score REPUTATION_DECAY_RATE) u100)))
    (- current-score decay-amount)
  )
)

(define-private (determine-reputation-tier (score uint))
  (if (>= score u90) u5
    (if (>= score u75) u4
      (if (>= score u60) u3
        (if (>= score u40) u2
          u1))))
)

(define-private (update-global-stats)
  (var-set total-reviews (+ (var-get total-reviews) u1))
)

;; Public functions
(define-public (register-user (initial-stake uint))
  (begin
    (asserts! (>= initial-stake MIN_STAKE_AMOUNT) ERR_INSUFFICIENT_STAKE)
    (asserts! (is-none (map-get? user-profiles { user: tx-sender })) ERR_INVALID_INPUT)
    
    (map-set user-profiles
      { user: tx-sender }
      {
        overall-score: u50, ;; Start with neutral score
        total-reviews-received: u0,
        total-reviews-given: u0,
        stake-amount: initial-stake,
        joined-at: block-height,
        last-activity: block-height,
        is-verified: false,
        reputation-tier: u1
      }
    )
    
    (var-set total-users (+ (var-get total-users) u1))
    (ok true)
  )
)

(define-public (create-domain (domain (string-ascii 20)) 
                             (name (string-ascii 50))
                             (description (string-ascii 200)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (validate-string-input domain) ERR_INVALID_INPUT)
    (asserts! (validate-string-input name) ERR_INVALID_INPUT)
    (asserts! (is-none (map-get? reputation-domains { domain: domain })) ERR_INVALID_INPUT)
    
    (map-set reputation-domains
      { domain: domain }
      {
        name: name,
        description: description,
        total-participants: u0,
        average-score: u50,
        is-active: true,
        created-at: block-height
      }
    )
    
    (var-set total-domains (+ (var-get total-domains) u1))
    (ok true)
  )
)

(define-public (submit-review (reviewee principal) 
                             (domain (string-ascii 20))
                             (rating uint)
                             (comment-hash (buff 32))
                             (stake-amount uint))
  (let (
    (reviewer-profile (unwrap! (map-get? user-profiles { user: tx-sender }) ERR_USER_NOT_FOUND))
    (reviewee-profile (unwrap! (map-get? user-profiles { user: reviewee }) ERR_USER_NOT_FOUND))
    (domain-info (unwrap! (map-get? reputation-domains { domain: domain }) ERR_DOMAIN_NOT_FOUND))
  )
    (asserts! (validate-rating rating) ERR_INVALID_INPUT)
    (asserts! (not (is-eq tx-sender reviewee)) ERR_SELF_REVIEW)
    (asserts! (>= stake-amount MIN_STAKE_AMOUNT) ERR_INSUFFICIENT_STAKE)
    (asserts! (get is-active domain-info) ERR_DOMAIN_NOT_FOUND)
    (asserts! (is-none (map-get? review-records { reviewer: tx-sender, reviewee: reviewee, domain: domain })) ERR_ALREADY_REVIEWED)
    
    (let (
      (review-weight (calculate-review-weight (get overall-score reviewer-profile) stake-amount))
      (current-domain-score (default-to 
        { score: u50, reviews-count: u0, weighted-average: u50, last-updated: u0, expertise-level: u1 }
        (map-get? domain-scores { user: reviewee, domain: domain })))
    )
      
      ;; Record the review
      (map-set review-records
        { reviewer: tx-sender, reviewee: reviewee, domain: domain }
        {
          rating: rating,
          weight: review-weight,
          comment-hash: comment-hash,
          created-at: block-height,
          is-disputed: false,
          stake-locked: stake-amount
        }
      )
      
      ;; Update reviewee's domain score
      (let ((new-weighted-score (calculate-weighted-score 
        (get weighted-average current-domain-score)
        (get reviews-count current-domain-score)
        rating
        review-weight)))
        
        (map-set domain-scores
          { user: reviewee, domain: domain }
          (merge current-domain-score {
            score: new-weighted-score,
            reviews-count: (+ (get reviews-count current-domain-score) u1),
            weighted-average: new-weighted-score,
            last-updated: block-height,
            expertise-level: (determine-reputation-tier new-weighted-score)
          })
        )
      )
      
      ;; Update reviewee's overall profile
      (let ((updated-overall-score (/ (+ (get overall-score reviewee-profile) rating) u2))) ;; Simple average
        (map-set user-profiles
          { user: reviewee }
          (merge reviewee-profile {
            overall-score: updated-overall-score,
            total-reviews-received: (+ (get total-reviews-received reviewee-profile) u1),
            last-activity: block-height,
            reputation-tier: (determine-reputation-tier updated-overall-score)
          })
        )
      )
      
      ;; Update reviewer's profile
      (map-set user-profiles
        { user: tx-sender }
        (merge reviewer-profile {
          total-reviews-given: (+ (get total-reviews-given reviewer-profile) u1),
          last-activity: block-height
        })
      )
      
      ;; Update domain statistics
      (map-set reputation-domains
        { domain: domain }
        (merge domain-info {
          total-participants: (+ (get total-participants domain-info) u1)
        })
      )
      
      (update-global-stats)
      (ok review-weight)
    )
  )
)

(define-public (add-attestation (user principal)
                               (attestation-type (string-ascii 30))
                               (value uint)
                               (confidence uint)
                               (expires-blocks (optional uint)))
  (let ((user-profile (unwrap! (map-get? user-profiles { user: user }) ERR_USER_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) (is-eq tx-sender user)) ERR_UNAUTHORIZED)
    (asserts! (validate-string-input attestation-type) ERR_INVALID_INPUT)
    (asserts! (<= confidence u100) ERR_INVALID_INPUT)
    
    (let ((expiry-block 
      (match expires-blocks
        some-blocks (some (+ block-height some-blocks))
        none)))
      
      (map-set attestations
        { attester: tx-sender, user: user, attestation-type: attestation-type }
        {
          value: value,
          confidence: confidence,
          created-at: block-height,
          expires-at: expiry-block,
          is-verified: (is-eq tx-sender CONTRACT_OWNER)
        }
      )
      
      ;; Boost user's reputation for verified attestations
      (if (is-eq tx-sender CONTRACT_OWNER)
        (begin
          (map-set user-profiles
            { user: user }
            (merge user-profile {
              overall-score: (min-uint u100 (+ (get overall-score user-profile) u5)),
              is-verified: true
            })
          )
          true
        )
        true
      )
      
      (ok true)
    )
  )
)

(define-public (apply-decay-to-user (user principal))
  (let ((user-profile (unwrap! (map-get? user-profiles { user: user }) ERR_USER_NOT_FOUND)))
    ;; Only apply decay if user has been inactive for significant period
    (if (> (- block-height (get last-activity user-profile)) u1008) ;; ~1 week
      (let ((decayed-score (apply-reputation-decay (get overall-score user-profile))))
        (map-set user-profiles
          { user: user }
          (merge user-profile {
            overall-score: decayed-score,
            reputation-tier: (determine-reputation-tier decayed-score)
          })
        )
        (ok decayed-score)
      )
      (ok (get overall-score user-profile))
    )
  )
)

(define-public (increase-stake (additional-amount uint))
  (let ((user-profile (unwrap! (map-get? user-profiles { user: tx-sender }) ERR_USER_NOT_FOUND)))
    (asserts! (> additional-amount u0) ERR_INVALID_INPUT)
    
    (map-set user-profiles
      { user: tx-sender }
      (merge user-profile {
        stake-amount: (+ (get stake-amount user-profile) additional-amount),
        last-activity: block-height
      })
    )
    (ok (+ (get stake-amount user-profile) additional-amount))
  )
)

;; Helper function to implement min for uints
(define-private (min-uint (a uint) (b uint))
  (if (<= a b) a b)
)

;; Read-only functions
(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

(define-read-only (get-domain-score (user principal) (domain (string-ascii 20)))
  (map-get? domain-scores { user: user, domain: domain })
)

(define-read-only (get-review (reviewer principal) (reviewee principal) (domain (string-ascii 20)))
  (map-get? review-records { reviewer: reviewer, reviewee: reviewee, domain: domain })
)

(define-read-only (get-domain-info (domain (string-ascii 20)))
  (map-get? reputation-domains { domain: domain })
)

(define-read-only (calculate-trust-score (user principal) (domain (string-ascii 20)))
  (let (
    (user-profile (map-get? user-profiles { user: user }))
    (domain-score (map-get? domain-scores { user: user, domain: domain }))
  )
    (match user-profile
      some-profile
        (match domain-score
          some-domain
            (ok {
              overall-reputation: (get overall-score some-profile),
              domain-expertise: (get score some-domain),
              trust-factor: (/ (+ (get overall-score some-profile) (get score some-domain)) u2),
              reputation-tier: (get reputation-tier some-profile),
              is-verified: (get is-verified some-profile)
            })
          (ok {
            overall-reputation: (get overall-score some-profile),
            domain-expertise: u0,
            trust-factor: (/ (get overall-score some-profile) u2),
            reputation-tier: (get reputation-tier some-profile),
            is-verified: (get is-verified some-profile)
          })
        )
      (err ERR_USER_NOT_FOUND)
    )
  )
)

(define-read-only (get-platform-stats)
  (ok {
    total-users: (var-get total-users),
    total-reviews: (var-get total-reviews),
    total-domains: (var-get total-domains),
    global-average-score: (var-get global-average-score),
    current-period: (var-get reputation-period)
  })
)