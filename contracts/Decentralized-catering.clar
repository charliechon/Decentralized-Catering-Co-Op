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
(define-constant ERR-MILESTONE-NOT-FOUND (err u110))
(define-constant ERR-MILESTONE-COMPLETED (err u111))
(define-constant ERR-CONTRACT-NOT-FOUND (err u112))
(define-constant ERR-INSUFFICIENT-ESCROW (err u113))
(define-constant ERR-DISPUTE-ACTIVE (err u114))
(define-constant ERR-NOT-CLIENT (err u115))
(define-constant ERR-INVALID-MILESTONE (err u116))
(define-constant ERR-NO-DIVIDENDS (err u117))
(define-constant ERR-ALREADY-CLAIMED (err u118))

(define-constant MIN-CONTRIBUTION u1000000)
(define-constant VOTING-PERIOD u144)
(define-constant MIN-QUORUM u50)

(define-data-var contract-owner principal tx-sender)
(define-data-var next-proposal-id uint u1)
(define-data-var next-bid-id uint u1)
(define-data-var total-treasury uint u0)
(define-data-var next-contract-id uint u1)
(define-data-var next-milestone-id uint u1)
(define-data-var total-escrowed uint u0)
(define-data-var next-dividend-pool-id uint u1)
(define-data-var total-dividends-distributed uint u0)

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

(define-map escrow-contracts uint {
    bid-id: uint,
    client: principal,
    caterer: principal,
    total-amount: uint,
    escrowed-amount: uint,
    released-amount: uint,
    created-at: uint,
    completed: bool,
    disputed: bool
})

(define-map contract-milestones {contract-id: uint, milestone-id: uint} {
    title: (string-ascii 64),
    description: (string-ascii 256),
    payment-amount: uint,
    completed: bool,
    completed-at: (optional uint),
    disputed: bool,
    dispute-votes-for: uint,
    dispute-votes-against: uint
})

(define-map milestone-disputes {contract-id: uint, milestone-id: uint, voter: principal} {
    vote: bool,
    voting-power: uint
})

(define-map dividend-pools uint {
    source-contract-id: uint,
    total-amount: uint,
    total-contribution-snapshot: uint,
    created-at: uint,
    distributed: bool,
    claimed-amount: uint
})

(define-map dividend-claims {pool-id: uint, member: principal} {
    claimed: bool,
    claim-amount: uint,
    claimed-at: (optional uint)
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

(define-public (create-escrow-contract (bid-id uint) (client principal) (total-amount uint))
    (let (
        (contract-id (var-get next-contract-id))
        (bid-data (unwrap! (map-get? bids bid-id) ERR-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
        (asserts! (get selected bid-data) ERR-UNAUTHORIZED)
        (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
        
        (map-set escrow-contracts contract-id {
            bid-id: bid-id,
            client: client,
            caterer: (get caterer bid-data),
            total-amount: total-amount,
            escrowed-amount: u0,
            released-amount: u0,
            created-at: stacks-block-height,
            completed: false,
            disputed: false
        })
        
        (var-set next-contract-id (+ contract-id u1))
        (ok contract-id)
    )
)

(define-public (create-milestone (contract-id uint) (title (string-ascii 64)) (description (string-ascii 256)) (payment-amount uint))
    (let (
        (milestone-id (var-get next-milestone-id))
        (contract-data (unwrap! (map-get? escrow-contracts contract-id) ERR-CONTRACT-NOT-FOUND))
        (caller tx-sender)
    )
        (asserts! (is-eq caller (get client contract-data)) ERR-NOT-CLIENT)
        (asserts! (> payment-amount u0) ERR-INVALID-AMOUNT)
        
        (map-set contract-milestones {contract-id: contract-id, milestone-id: milestone-id} {
            title: title,
            description: description,
            payment-amount: payment-amount,
            completed: false,
            completed-at: none,
            disputed: false,
            dispute-votes-for: u0,
            dispute-votes-against: u0
        })
        
        (var-set next-milestone-id (+ milestone-id u1))
        (ok milestone-id)
    )
)

(define-public (deposit-escrow (contract-id uint) (amount uint))
    (let (
        (contract-data (unwrap! (map-get? escrow-contracts contract-id) ERR-CONTRACT-NOT-FOUND))
        (caller tx-sender)
    )
        (asserts! (is-eq caller (get client contract-data)) ERR-NOT-CLIENT)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        (try! (stx-transfer? amount caller (as-contract tx-sender)))
        
        (map-set escrow-contracts contract-id
            (merge contract-data {
                escrowed-amount: (+ (get escrowed-amount contract-data) amount)
            })
        )
        
        (var-set total-escrowed (+ (var-get total-escrowed) amount))
        (ok true)
    )
)

(define-public (complete-milestone (contract-id uint) (milestone-id uint))
    (let (
        (contract-data (unwrap! (map-get? escrow-contracts contract-id) ERR-CONTRACT-NOT-FOUND))
        (milestone-data (unwrap! (map-get? contract-milestones {contract-id: contract-id, milestone-id: milestone-id}) ERR-MILESTONE-NOT-FOUND))
        (caller tx-sender)
    )
        (asserts! (is-eq caller (get caterer contract-data)) ERR-UNAUTHORIZED)
        (asserts! (not (get completed milestone-data)) ERR-MILESTONE-COMPLETED)
        (asserts! (not (get disputed milestone-data)) ERR-DISPUTE-ACTIVE)
        (asserts! (>= (get escrowed-amount contract-data) (get payment-amount milestone-data)) ERR-INSUFFICIENT-ESCROW)
        
        (map-set contract-milestones {contract-id: contract-id, milestone-id: milestone-id}
            (merge milestone-data {
                completed: true,
                completed-at: (some stacks-block-height)
            })
        )
        
        (try! (as-contract (stx-transfer? (get payment-amount milestone-data) tx-sender (get caterer contract-data))))
        
        (map-set escrow-contracts contract-id
            (merge contract-data {
                escrowed-amount: (- (get escrowed-amount contract-data) (get payment-amount milestone-data)),
                released-amount: (+ (get released-amount contract-data) (get payment-amount milestone-data))
            })
        )
        
        (var-set total-escrowed (- (var-get total-escrowed) (get payment-amount milestone-data)))
        (ok true)
    )
)

(define-public (dispute-milestone (contract-id uint) (milestone-id uint))
    (let (
        (contract-data (unwrap! (map-get? escrow-contracts contract-id) ERR-CONTRACT-NOT-FOUND))
        (milestone-data (unwrap! (map-get? contract-milestones {contract-id: contract-id, milestone-id: milestone-id}) ERR-MILESTONE-NOT-FOUND))
        (caller tx-sender)
    )
        (asserts! (is-eq caller (get client contract-data)) ERR-NOT-CLIENT)
        (asserts! (get completed milestone-data) ERR-INVALID-MILESTONE)
        (asserts! (not (get disputed milestone-data)) ERR-DISPUTE-ACTIVE)
        
        (map-set contract-milestones {contract-id: contract-id, milestone-id: milestone-id}
            (merge milestone-data {disputed: true})
        )
        
        (map-set escrow-contracts contract-id
            (merge contract-data {disputed: true})
        )
        
        (ok true)
    )
)

(define-public (vote-on-dispute (contract-id uint) (milestone-id uint) (vote bool))
    (let (
        (caller tx-sender)
        (member-data (unwrap! (map-get? members caller) ERR-NOT-MEMBER))
        (milestone-data (unwrap! (map-get? contract-milestones {contract-id: contract-id, milestone-id: milestone-id}) ERR-MILESTONE-NOT-FOUND))
        (vote-key {contract-id: contract-id, milestone-id: milestone-id, voter: caller})
        (existing-vote (map-get? milestone-disputes vote-key))
    )
        (asserts! (get active member-data) ERR-NOT-MEMBER)
        (asserts! (get disputed milestone-data) ERR-INVALID-MILESTONE)
        (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
        
        (let (
            (voting-power (get voting-power member-data))
            (current-for (get dispute-votes-for milestone-data))
            (current-against (get dispute-votes-against milestone-data))
        )
            (map-set milestone-disputes vote-key {
                vote: vote,
                voting-power: voting-power
            })
            
            (map-set contract-milestones {contract-id: contract-id, milestone-id: milestone-id}
                (merge milestone-data {
                    dispute-votes-for: (if vote (+ current-for voting-power) current-for),
                    dispute-votes-against: (if vote current-against (+ current-against voting-power))
                })
            )
            (ok true)
        )
    )
)

(define-public (resolve-dispute (contract-id uint) (milestone-id uint))
    (let (
        (contract-data (unwrap! (map-get? escrow-contracts contract-id) ERR-CONTRACT-NOT-FOUND))
        (milestone-data (unwrap! (map-get? contract-milestones {contract-id: contract-id, milestone-id: milestone-id}) ERR-MILESTONE-NOT-FOUND))
        (total-dispute-votes (+ (get dispute-votes-for milestone-data) (get dispute-votes-against milestone-data)))
        (dispute-approved (> (get dispute-votes-for milestone-data) (get dispute-votes-against milestone-data)))
    )
        (asserts! (get disputed milestone-data) ERR-INVALID-MILESTONE)
        (asserts! (>= total-dispute-votes MIN-QUORUM) ERR-INVALID-AMOUNT)
        
        (if dispute-approved
            (begin
                (try! (as-contract (stx-transfer? (get payment-amount milestone-data) tx-sender (get client contract-data))))
                
                (map-set escrow-contracts contract-id
                    (merge contract-data {
                        escrowed-amount: (- (get escrowed-amount contract-data) (get payment-amount milestone-data)),
                        disputed: false
                    })
                )
                
                (map-set contract-milestones {contract-id: contract-id, milestone-id: milestone-id}
                    (merge milestone-data {
                        completed: false,
                        completed-at: none,
                        disputed: false
                    })
                )
            )
            (begin
                (map-set contract-milestones {contract-id: contract-id, milestone-id: milestone-id}
                    (merge milestone-data {disputed: false})
                )
                
                (map-set escrow-contracts contract-id
                    (merge contract-data {disputed: false})
                )
            )
        )
        
        (var-set total-escrowed (- (var-get total-escrowed) (get payment-amount milestone-data)))
        (ok dispute-approved)
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

(define-read-only (get-escrow-contract (contract-id uint))
    (map-get? escrow-contracts contract-id)
)

(define-read-only (get-contract-milestone (contract-id uint) (milestone-id uint))
    (map-get? contract-milestones {contract-id: contract-id, milestone-id: milestone-id})
)

(define-read-only (get-milestone-dispute-vote (contract-id uint) (milestone-id uint) (voter principal))
    (map-get? milestone-disputes {contract-id: contract-id, milestone-id: milestone-id, voter: voter})
)

(define-read-only (get-total-escrowed)
    (var-get total-escrowed)
)

(define-read-only (get-contract-progress (contract-id uint))
    (match (map-get? escrow-contracts contract-id)
        contract-data (ok {
            total-amount: (get total-amount contract-data),
            escrowed-amount: (get escrowed-amount contract-data),
            released-amount: (get released-amount contract-data),
            completion-percentage: (if (> (get total-amount contract-data) u0)
                (/ (* (get released-amount contract-data) u100) (get total-amount contract-data))
                u0
            ),
            disputed: (get disputed contract-data),
            completed: (get completed contract-data)
        })
        ERR-CONTRACT-NOT-FOUND
    )
)

(define-public (create-dividend-pool (source-contract-id uint) (profit-amount uint))
    (let (
        (pool-id (var-get next-dividend-pool-id))
        (contract-data (unwrap! (map-get? escrow-contracts source-contract-id) ERR-CONTRACT-NOT-FOUND))
        (current-treasury (var-get total-treasury))
    )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
        (asserts! (> profit-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (get completed contract-data) ERR-INVALID-MILESTONE)
        
        (try! (stx-transfer? profit-amount tx-sender (as-contract tx-sender)))
        
        (map-set dividend-pools pool-id {
            source-contract-id: source-contract-id,
            total-amount: profit-amount,
            total-contribution-snapshot: current-treasury,
            created-at: stacks-block-height,
            distributed: false,
            claimed-amount: u0
        })
        
        (var-set next-dividend-pool-id (+ pool-id u1))
        (ok pool-id)
    )
)

(define-public (claim-dividend (pool-id uint))
    (let (
        (pool-data (unwrap! (map-get? dividend-pools pool-id) ERR-NOT-FOUND))
        (member-data (unwrap! (map-get? members tx-sender) ERR-NOT-MEMBER))
        (claim-key {pool-id: pool-id, member: tx-sender})
        (existing-claim (map-get? dividend-claims claim-key))
    )
        (asserts! (get active member-data) ERR-NOT-MEMBER)
        (asserts! (is-none existing-claim) ERR-ALREADY-CLAIMED)
        
        (let (
            (member-contribution (get contribution member-data))
            (total-snapshot (get total-contribution-snapshot pool-data))
            (dividend-share (if (> total-snapshot u0)
                (/ (* (get total-amount pool-data) member-contribution) total-snapshot)
                u0
            ))
        )
            (asserts! (> dividend-share u0) ERR-NO-DIVIDENDS)
            
            (try! (as-contract (stx-transfer? dividend-share tx-sender tx-sender)))
            
            (map-set dividend-claims claim-key {
                claimed: true,
                claim-amount: dividend-share,
                claimed-at: (some stacks-block-height)
            })
            
            (map-set dividend-pools pool-id
                (merge pool-data {
                    claimed-amount: (+ (get claimed-amount pool-data) dividend-share)
                })
            )
            
            (var-set total-dividends-distributed (+ (var-get total-dividends-distributed) dividend-share))
            (ok dividend-share)
        )
    )
)

(define-public (mark-pool-distributed (pool-id uint))
    (let (
        (pool-data (unwrap! (map-get? dividend-pools pool-id) ERR-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
        (asserts! (not (get distributed pool-data)) ERR-ALREADY-EXISTS)
        
        (map-set dividend-pools pool-id
            (merge pool-data {distributed: true})
        )
        (ok true)
    )
)

(define-read-only (get-dividend-pool (pool-id uint))
    (map-get? dividend-pools pool-id)
)

(define-read-only (get-dividend-claim (pool-id uint) (member principal))
    (map-get? dividend-claims {pool-id: pool-id, member: member})
)

(define-read-only (calculate-member-dividend-share (pool-id uint) (member principal))
    (match (map-get? dividend-pools pool-id)
        pool-data
            (match (map-get? members member)
                member-data
                    (let (
                        (member-contribution (get contribution member-data))
                        (total-snapshot (get total-contribution-snapshot pool-data))
                        (share (if (> total-snapshot u0)
                            (/ (* (get total-amount pool-data) member-contribution) total-snapshot)
                            u0
                        ))
                    )
                        (ok {
                            eligible-amount: share,
                            member-contribution: member-contribution,
                            total-pool: (get total-amount pool-data),
                            contribution-percentage: (if (> total-snapshot u0)
                                (/ (* member-contribution u10000) total-snapshot)
                                u0
                            )
                        })
                    )
                ERR-NOT-MEMBER
            )
        ERR-NOT-FOUND
    )
)

(define-read-only (get-total-dividends-distributed)
    (var-get total-dividends-distributed)
)

(define-read-only (get-unclaimed-dividends (pool-id uint))
    (match (map-get? dividend-pools pool-id)
        pool-data (ok (- (get total-amount pool-data) (get claimed-amount pool-data)))
        ERR-NOT-FOUND
    )
)

(define-read-only (get-member-dividend-history (member principal))
    (ok {
        total-pools-available: (- (var-get next-dividend-pool-id) u1),
        total-dividends-distributed: (var-get total-dividends-distributed)
    })
)
