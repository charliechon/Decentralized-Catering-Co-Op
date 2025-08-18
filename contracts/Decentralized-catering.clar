;; title: Decentralized-catering
;; version: 1.0.0
;; summary: A DAO for small caterers to pool funds and bid on large contracts
;; description: Enables small catering businesses to form a cooperative and bid on contracts they couldn't handle individually

(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-VOTING-PERIOD-ENDED (err u104))
(define-constant ERR-VOTING-PERIOD-ACTIVE (err u105))
(define-constant ERR-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-ALREADY-VOTED (err u107))
(define-constant ERR-NOT-MEMBER (err u108))
(define-constant ERR-PROPOSAL-EXPIRED (err u109))

(define-constant MIN-CONTRIBUTION u1000000)
(define-constant VOTING-PERIOD u144)
(define-constant MIN-QUORUM u50)

(define-data-var contract-owner principal tx-sender)
(define-data-var next-proposal-id uint u1)
(define-data-var next-bid-id uint u1)
(define-data-var total-treasury uint u0)

(define-map members principal {
    contribution: uint,
    voting-power: uint,
    joined-at: uint,
    active: bool
})

(define-map proposals uint {
    proposer: principal,
    title: (string-ascii 64),
    description: (string-ascii 256),
    contract-value: uint,
    required-funds: uint,
    votes-for: uint,
    votes-against: uint,
    created-at: uint,
    voting-ends: uint,
    executed: bool,
    approved: bool
})

(define-map votes {proposal-id: uint, voter: principal} {
    vote: bool,
    voting-power: uint
})

(define-map bids uint {
    proposal-id: uint,
    caterer: principal,
    amount: uint,
    description: (string-ascii 256),
    selected: bool,
    created-at: uint
})

(define-map caterer-profiles principal {
    name: (string-ascii 32),
    specialties: (string-ascii 128),
    capacity: uint,
    rating: uint,
    total-contracts: uint
})

(define-public (join-coop (contribution uint))
    (let (
        (caller tx-sender)
        (current-member (map-get? members caller))
    )
        (asserts! (>= contribution MIN-CONTRIBUTION) ERR-INVALID-AMOUNT)
        (asserts! (is-none current-member) ERR-ALREADY-EXISTS)
        
        (try! (stx-transfer? contribution caller (as-contract tx-sender)))
        
        (let (
            (voting-power (/ contribution u1000))
        )
            (map-set members caller {
                contribution: contribution,
                voting-power: voting-power,
                joined-at: stacks-block-height,
                active: true
            })
            
            (var-set total-treasury (+ (var-get total-treasury) contribution))
            (ok true)
        )
    )
)

(define-public (create-proposal (title (string-ascii 64)) (description (string-ascii 256)) (contract-value uint) (required-funds uint))
    (let (
        (proposal-id (var-get next-proposal-id))
        (caller tx-sender)
        (member-data (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
    )
        (asserts! (get active member-data) ERR-NOT-MEMBER)
        (asserts! (> contract-value u0) ERR-INVALID-AMOUNT)
        (asserts! (> required-funds u0) ERR-INVALID-AMOUNT)
        
        (map-set proposals proposal-id {
            proposer: caller,
            title: title,
            description: description,
            contract-value: contract-value,
            required-funds: required-funds,
            votes-for: u0,
            votes-against: u0,
            created-at: stacks-block-height,
            voting-ends: (+ stacks-block-height VOTING-PERIOD),
            executed: false,
            approved: false
        })
        
        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (vote bool))
    (let (
        (caller tx-sender)
        (member-data (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
        (proposal-data (unwrap! (map-get? proposals proposal-id) ERR-NOT-FOUND))
        (vote-key {proposal-id: proposal-id, voter: caller})
        (existing-vote (map-get? votes vote-key))
    )
        (asserts! (get active member-data) ERR-NOT-MEMBER)
        (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
        (asserts! (<= stacks-block-height (get voting-ends proposal-data)) ERR-VOTING-PERIOD-ENDED)
        
        (let (
            (voting-power (get voting-power member-data))
            (current-for (get votes-for proposal-data))
            (current-against (get votes-against proposal-data))
        )
            (map-set votes vote-key {
                vote: vote,
                voting-power: voting-power
            })
            
            (map-set proposals proposal-id
                (merge proposal-data {
                    votes-for: (if vote (+ current-for voting-power) current-for),
                    votes-against: (if vote current-against (+ current-against voting-power))
                })
            )
            (ok true)
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal-data (unwrap! (map-get? proposals proposal-id) ERR-NOT-FOUND))
        (total-votes (+ (get votes-for proposal-data) (get votes-against proposal-data)))
    )
        (asserts! (> stacks-block-height (get voting-ends proposal-data)) ERR-VOTING-PERIOD-ACTIVE)
        (asserts! (not (get executed proposal-data)) ERR-ALREADY-EXISTS)
        (asserts! (>= total-votes MIN-QUORUM) ERR-INVALID-AMOUNT)
        
        (let (
            (approved (> (get votes-for proposal-data) (get votes-against proposal-data)))
        )
            (map-set proposals proposal-id
                (merge proposal-data {
                    executed: true,
                    approved: approved
                })
            )
            (ok approved)
        )
    )
)

(define-public (submit-bid (proposal-id uint) (amount uint) (description (string-ascii 256)))
    (let (
        (caller tx-sender)
        (member-data (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
        (proposal-data (unwrap! (map-get? proposals proposal-id) ERR-NOT-FOUND))
        (bid-id (var-get next-bid-id))
    )
        (asserts! (get active member-data) ERR-NOT-MEMBER)
        (asserts! (get approved proposal-data) ERR-UNAUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        (map-set bids bid-id {
            proposal-id: proposal-id,
            caterer: caller,
            amount: amount,
            description: description,
            selected: false,
            created-at: stacks-block-height
        })
        
        (var-set next-bid-id (+ bid-id u1))
        (ok bid-id)
    )
)

(define-public (select-bid (bid-id uint))
    (let (
        (caller tx-sender)
        (bid-data (unwrap! (map-get? bids bid-id) ERR-NOT-FOUND))
        (proposal-data (unwrap! (map-get? proposals (get proposal-id bid-data)) ERR-NOT-FOUND))
    )
        (asserts! (is-eq caller (var-get contract-owner)) ERR-UNAUTHORIZED)
        (asserts! (get approved proposal-data) ERR-UNAUTHORIZED)
        (asserts! (<= (get required-funds proposal-data) (var-get total-treasury)) ERR-INSUFFICIENT-FUNDS)
        
        (map-set bids bid-id (merge bid-data {selected: true}))
        
        (try! (as-contract (stx-transfer? (get required-funds proposal-data) tx-sender (get caterer bid-data))))
        (var-set total-treasury (- (var-get total-treasury) (get required-funds proposal-data)))
        
        (let (
            (caterer-profile (default-to 
                {name: "", specialties: "", capacity: u0, rating: u0, total-contracts: u0}
                (map-get? caterer-profiles (get caterer bid-data))
            ))
        )
            (map-set caterer-profiles (get caterer bid-data)
                (merge caterer-profile {
                    total-contracts: (+ (get total-contracts caterer-profile) u1)
                })
            )
        )
        (ok true)
    )
)

(define-public (update-caterer-profile (name (string-ascii 32)) (specialties (string-ascii 128)) (capacity uint))
    (let (
        (caller tx-sender)
        (member-data (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
    )
        (asserts! (get active member-data) ERR-NOT-MEMBER)
        
        (let (
            (current-profile (default-to 
                {name: "", specialties: "", capacity: u0, rating: u0, total-contracts: u0}
                (map-get? caterer-profiles caller)
            ))
        )
            (map-set caterer-profiles caller
                (merge current-profile {
                    name: name,
                    specialties: specialties,
                    capacity: capacity
                })
            )
            (ok true)
        )
    )
)

(define-public (rate-caterer (caterer principal) (rating uint))
    (let (
        (caller tx-sender)
        (member-data (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
        (caterer-profile (unwrap! (map-get? caterer-profiles caterer) ERR-NOT-FOUND))
    )
        (asserts! (get active member-data) ERR-NOT-MEMBER)
        (asserts! (<= rating u5) ERR-INVALID-AMOUNT)
        (asserts! (>= rating u1) ERR-INVALID-AMOUNT)
        
        (map-set caterer-profiles caterer
            (merge caterer-profile {
                rating: rating
            })
        )
        (ok true)
    )
)

(define-read-only (get-member (member principal))
    (map-get? members member)
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-bid (bid-id uint))
    (map-get? bids bid-id)
)

(define-read-only (get-caterer-profile (caterer principal))
    (map-get? caterer-profiles caterer)
)

(define-read-only (get-treasury-balance)
    (var-get total-treasury)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-contract-owner)
    (var-get contract-owner)
)
