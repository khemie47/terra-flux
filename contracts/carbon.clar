;; Terraflux - Decentralized Environmental Impact Ledger

;; Error codes
(define-constant ERR_ACCESS_DENIED (err u100))
(define-constant ERR_PROJECT_DUPLICATE (err u101))
(define-constant ERR_PROJECT_UNKNOWN (err u102))
(define-constant ERR_PLATFORM_OFFLINE (err u103))
(define-constant ERR_INSUFFICIENT_BONDS (err u104))
(define-constant ERR_ASSESSMENT_LOCKOUT (err u105))
(define-constant ERR_CAPACITY_LIMIT (err u106))
(define-constant ERR_SCHEDULE_CONFLICT (err u107))
(define-constant ERR_MALFORMED_PROJECT_CODE (err u400))
(define-constant ERR_INVALID_EMISSION_DATA (err u401))
(define-constant ERR_INSUFFICIENT_DOCUMENTATION (err u402))
(define-constant ERR_INVALID_CARBON_RATING (err u403))
(define-constant ERR_INVALID_STANDARD_LEVEL (err u404))
(define-constant ERR_INVALID_AUDITOR_CREDENTIALS (err u405))

;; System constants
(define-constant ASSESSMENT_INTERVAL_SECONDS u86400) ;; 24 hours in seconds
(define-constant MINIMUM_AUDITOR_BOND u1000000) ;; in microSTX
(define-constant REQUIRED_AUDITOR_CERTIFICATION u50)
(define-constant MAX_DOCUMENTATION_LENGTH u500)

;; Input validation functions
(define-private (validate-project-code (project_code (string-ascii 255)))
    (begin
        (ok true)))(asserts! (>= (len project_code) u3) (err "Project code too short"))
        (asserts! (<= (len project_code) u255) (err "Project code too long"))
        (asserts! (is-eq (index-of project_code ".") none) (err "Invalid character: ."))
        (asserts! (is-eq (index-of project_code "/") none) (err "Invalid character: /"))
        (asserts! (is-eq (index-of project_code " ") none) (err "Invalid character: space"))
        (ok true)))

(define-private (validate-emission-certificate (carbon_certificate (string-ascii 50)))
    (begin
        (asserts! (>= (len carbon_certificate) u5) (err "Carbon certificate too short"))
        (asserts! (<= (len carbon_certificate) u50) (err "Carbon certificate too long"))
        (asserts! (is-eq (index-of carbon_certificate "<") none) (err "Invalid character: <"))
        (asserts! (is-eq (index-of carbon_certificate ">") none) (err "Invalid character: >"))
        (ok true)))

(define-private (validate-impact-documentation (impact_report (string-ascii 500)))
    (begin
        (asserts! (>= (len impact_report) u10) (err "Impact documentation too short"))
        (asserts! (<= (len impact_report) u500) (err "Impact documentation too long"))
        (asserts! (is-eq (index-of impact_report "<") none) (err "Invalid character: <"))
        (asserts! (is-eq (index-of impact_report ">") none) (err "Invalid character: >"))
        (ok true)))

(define-private (validate-carbon-efficiency (emission_reduction uint))
    (begin
        (asserts! (>= emission_reduction u1) (err "Emission reduction too low"))
        (asserts! (<= emission_reduction u100) (err "Emission reduction too high"))
        (ok true)))

(define-private (validate-standard-compliance (compliance_tier uint))
    (begin
        (asserts! (>= compliance_tier u1) (err "Compliance tier too low"))
        (asserts! (<= compliance_tier u10) (err "Compliance tier too high"))
        (ok true)))

;; Administrative state variables
(define-data-var platform_coordinator principal tx-sender)
(define-data-var project_listing_fee uint u100)
(define-data-var required_impact_validations uint u5)
(define-data-var global_compliance_standard uint u1)
(define-data-var platform_maintenance_mode bool false)

;; Primary data structures
(define-map registered_carbon_projects
    {project_code: (string-ascii 255)}
    {
        project_developer: principal,
        compliance_tier: (string-ascii 20),
        registration_timestamp: uint,
        greenwashing_risk_score: uint,
        total_fraud_allegations: uint,
        auditor_bond_locked: uint,
        last_impact_assessment: uint,
        carbon_certificate: (string-ascii 50)
    })

(define-map fraud_allegation_cases
    {project_code: (string-ascii 255)}
    {
        whistleblower_address: principal,
        allegation_timestamp: uint,
        impact_evidence: (string-ascii 500),
        case_status: (string-ascii 20),
        fraud_likelihood: uint,
        stakeholder_count: uint
    })

(define-map auditor_project_assignments
    {auditor_address: principal, assigned_project: (string-ascii 255)}
    {
        assessment_count: uint,
        last_assessment_date: uint,
        auditor_credibility: uint,
        bonded_capital: uint,
        validated_assessments: uint
    })

(define-map project_assessment_records
    {project_code: (string-ascii 255)}
    {
        assessment_schedule: uint,
        last_assessment_timestamp: uint,
        lead_auditor: principal,
        assessment_score: uint,
        regulatory_notes: (string-ascii 50)
    })

(define-map carbon_auditor_registry
    {auditor_address: principal}
    {
        bonded_tokens: uint,
        completed_audits: uint,
        professional_rating: uint,
        last_audit_timestamp: uint,
        auditor_standing: (string-ascii 20)
    })

;; Query functions
(define-read-only (get-project-compliance-status (project_code (string-ascii 255)))
    (match (map-get? registered_carbon_projects {project_code: project_code})
        project_details (ok project_details)
        (err ERR_PROJECT_UNKNOWN)))

(define-read-only (has_fraud_allegations (project_code (string-ascii 255)))
    (is-some (map-get? fraud_allegation_cases {project_code: project_code})))

(define-read-only (get-auditor-professional-rating (auditor_address principal))
    (match (map-get? auditor_project_assignments {auditor_address: auditor_address, assigned_project: ""})
        auditor_record (get auditor_credibility auditor_record)
        u0))

;; Core operations
(define-public (register-carbon-project 
    (project_code (string-ascii 255))
    (carbon_certificate (string-ascii 50)))
    (let (
        (current_timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
        (required_bond (* MINIMUM_AUDITOR_BOND (var-get global_compliance_standard))))
        
        ;; Input validation
        (asserts! (is-ok (validate-project-code project_code)) ERR_MALFORMED_PROJECT_CODE)
        (asserts! (is-ok (validate-emission-certificate carbon_certificate)) ERR_INVALID_EMISSION_DATA)
        (asserts! (is-eq tx-sender (var-get platform_coordinator)) ERR_ACCESS_DENIED)
        (asserts! (>= (stx-get-balance tx-sender) required_bond) ERR_INSUFFICIENT_BONDS)
        
        (match (map-get? registered_carbon_projects {project_code: project_code})
            existing_project ERR_PROJECT_DUPLICATE
            (begin
                (try! (stx-transfer? required_bond tx-sender (as-contract tx-sender)))
                (map-set registered_carbon_projects
                    {project_code: project_code}
                    {
                        project_developer: tx-sender,
                        compliance_tier: "certified",
                        registration_timestamp: current_timestamp,
                        greenwashing_risk_score: u0,
                        total_fraud_allegations: u0,
                        auditor_bond_locked: required_bond,
                        last_impact_assessment: current_timestamp,
                        carbon_certificate: carbon_certificate
                    })
                (ok true)))))

(define-public (submit-fraud-allegation 
    (project_code (string-ascii 255)) 
    (impact_evidence (string-ascii 500))
    (fraud_likelihood uint))
    (let (
        (current_timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
        (auditor_record (default-to 
            {assessment_count: u0, last_assessment_date: u0, auditor_credibility: u0, bonded_capital: u0, validated_assessments: u0}
            (map-get? auditor_project_assignments {auditor_address: tx-sender, assigned_project: project_code}))))
        
        ;; Input validation
        (asserts! (is-ok (validate-project-code project_code)) ERR_MALFORMED_PROJECT_CODE)
        (asserts! (is-ok (validate-impact-documentation impact_evidence)) ERR_INSUFFICIENT_DOCUMENTATION)
        (asserts! (is-ok (validate-carbon-efficiency fraud_likelihood)) ERR_INVALID_CARBON_RATING)
        (asserts! (not (var-get platform_maintenance_mode)) ERR_PLATFORM_OFFLINE)
        (asserts! (>= (get auditor_credibility auditor_record) REQUIRED_AUDITOR_CERTIFICATION) ERR_INSUFFICIENT_BONDS)
        (asserts! (> (- current_timestamp (get last_assessment_date auditor_record)) ASSESSMENT_INTERVAL_SECONDS) ERR_ASSESSMENT_LOCKOUT)
        
        (map-set fraud_allegation_cases
            {project_code: project_code}
            {
                whistleblower_address: tx-sender,
                allegation_timestamp: current_timestamp,
                impact_evidence: impact_evidence,
                case_status: "investigating",
                fraud_likelihood: fraud_likelihood,
                stakeholder_count: u1
            })
        
        (map-set auditor_project_assignments
            {auditor_address: tx-sender, assigned_project: project_code}
            {
                assessment_count: (+ (get assessment_count auditor_record) u1),
                last_assessment_date: current_timestamp,
                auditor_credibility: (+ (get auditor_credibility auditor_record) u5),
                bonded_capital: (get bonded_capital auditor_record),
                validated_assessments: (get validated_assessments auditor_record)
            })
        (ok true)))

(define-private (update-project-risk-assessment (project_code (string-ascii 255)) (risk_delta int))
    (begin 
        (asserts! (is-ok (validate-project-code project_code)) ERR_MALFORMED_PROJECT_CODE)
        (match (map-get? registered_carbon_projects {project_code: project_code})
            project_details 
                (begin
                    (map-set registered_carbon_projects
                        {project_code: project_code}
                        (merge project_details {
                            greenwashing_risk_score: (+ (get greenwashing_risk_score project_details) 
                                (if (> risk_delta 0) 
                                    (to-uint risk_delta)
                                    u0))
                        }))
                    (ok true))
            ERR_PROJECT_UNKNOWN)))

(define-public (validate-fraud-allegation 
    (project_code (string-ascii 255))
    (allegation_confirmed bool))
    (let (
        (current_timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
        (auditor_profile (unwrap! (map-get? carbon_auditor_registry {auditor_address: tx-sender}) ERR_ACCESS_DENIED)))
        
        (asserts! (is-ok (validate-project-code project_code)) ERR_MALFORMED_PROJECT_CODE)
        (asserts! (>= (get bonded_tokens auditor_profile) MINIMUM_AUDITOR_BOND) ERR_INSUFFICIENT_BONDS)
        
        (map-set carbon_auditor_registry
            {auditor_address: tx-sender}
            (merge auditor_profile {
                completed_audits: (+ (get completed_audits auditor_profile) u1),
                last_audit_timestamp: current_timestamp
            }))
        (if allegation_confirmed
            (update-project-risk-assessment project_code 10)
            (update-project-risk-assessment project_code -5))))

(define-public (register-carbon-auditor (bond_amount uint))
    (let (
        (current_timestamp (unwrap-panic (get-block-info? time (- block-height u1)))))
        (asserts! (>= bond_amount MINIMUM_AUDITOR_BOND) ERR_INSUFFICIENT_BONDS)
        (asserts! (>= (stx-get-balance tx-sender) bond_amount) ERR_INSUFFICIENT_BONDS)
        
        (map-set carbon_auditor_registry
            {auditor_address: tx-sender}
            {
                bonded_tokens: bond_amount,
                completed_audits: u0,
                professional_rating: u100,
                last_audit_timestamp: current_timestamp,
                auditor_standing: "certified"
            })
        (unwrap! (stx-transfer? bond_amount tx-sender (as-contract tx-sender))
                 ERR_INSUFFICIENT_BONDS)
        (ok true)))

;; System management functions
(define-public (update-compliance-standard (new_standard_level uint))
    (begin
        (asserts! (is-ok (validate-standard-compliance new_standard_level)) ERR_INVALID_STANDARD_LEVEL)
        (asserts! (is-eq tx-sender (var-get platform_coordinator)) ERR_ACCESS_DENIED)
        (var-set global_compliance_standard new_standard_level)
        (ok true)))

(define-public (set-platform-maintenance (maintenance_status bool))
    (begin
        (asserts! (is-eq tx-sender (var-get platform_coordinator)) ERR_ACCESS_DENIED)
        (var-set platform_maintenance_mode maintenance_status)
        (ok true)))

(define-public (transfer_platform_coordination (new_coordinator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get platform_coordinator)) ERR_ACCESS_DENIED)
        (asserts! (not (is-eq new_coordinator 'SP000000000000000000002Q6VF78)) ERR_INVALID_AUDITOR_CREDENTIALS)
        (var-set platform_coordinator new_coordinator)
        (ok true)))
