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
        (asserts! (>= (len project_code) u3) ERR_MALFORMED_PROJECT_CODE)
        (asserts! (<= (len project_code) u255) ERR_MALFORMED_PROJECT_CODE)
        (asserts! (is-eq (index-of project_code ".") none) ERR_MALFORMED_PROJECT_CODE)
        (asserts! (is-eq (index-of project_code "/") none) ERR_MALFORMED_PROJECT_CODE)
        (asserts! (is-eq (index-of project_code " ") none) ERR_MALFORMED_PROJECT_CODE)
        (ok project_code)))

(define-private (validate-emission-certificate (carbon_certificate (string-ascii 50)))
    (begin
        (asserts! (>= (len carbon_certificate) u5) ERR_INVALID_EMISSION_DATA)
        (asserts! (<= (len carbon_certificate) u50) ERR_INVALID_EMISSION_DATA)
        (asserts! (is-eq (index-of carbon_certificate "<") none) ERR_INVALID_EMISSION_DATA)
        (asserts! (is-eq (index-of carbon_certificate ">") none) ERR_INVALID_EMISSION_DATA)
        (ok carbon_certificate)))

(define-private (validate-impact-documentation (impact_report (string-ascii 500)))
    (begin
        (asserts! (>= (len impact_report) u10) ERR_INSUFFICIENT_DOCUMENTATION)
        (asserts! (<= (len impact_report) u500) ERR_INSUFFICIENT_DOCUMENTATION)
        (asserts! (is-eq (index-of impact_report "<") none) ERR_INSUFFICIENT_DOCUMENTATION)
        (asserts! (is-eq (index-of impact_report ">") none) ERR_INSUFFICIENT_DOCUMENTATION)
        (ok impact_report)))

(define-private (validate-carbon-efficiency (emission_reduction uint))
    (begin
        (asserts! (>= emission_reduction u1) ERR_INVALID_CARBON_RATING)
        (asserts! (<= emission_reduction u100) ERR_INVALID_CARBON_RATING)
        (ok emission_reduction)))

(define-private (validate-standard-compliance (compliance_tier uint))
    (begin
        (asserts! (>= compliance_tier u1) ERR_INVALID_STANDARD_LEVEL)
        (asserts! (<= compliance_tier u10) ERR_INVALID_STANDARD_LEVEL)
        (ok compliance_tier)))

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
    (let ((validated_project_code (unwrap! (validate-project-code project_code) ERR_MALFORMED_PROJECT_CODE)))
        (match (map-get? registered_carbon_projects {project_code: validated_project_code})
            project_details (ok project_details)
            ERR_PROJECT_UNKNOWN)))

(define-read-only (has-fraud-allegations (project_code (string-ascii 255)))
    (let ((validated_project_code (unwrap! (validate-project-code project_code) ERR_MALFORMED_PROJECT_CODE)))
        (ok (is-some (map-get? fraud_allegation_cases {project_code: validated_project_code})))))

(define-read-only (get-auditor-professional-rating (auditor_address principal))
    (match (map-get? carbon_auditor_registry {auditor_address: auditor_address})
        auditor_record (ok (get professional_rating auditor_record))
        (ok u0)))

(define-read-only (get-fraud-allegation-details (project_code (string-ascii 255)))
    (let ((validated_project_code (unwrap! (validate-project-code project_code) ERR_MALFORMED_PROJECT_CODE)))
        (match (map-get? fraud_allegation_cases {project_code: validated_project_code})
            allegation_details (ok allegation_details)
            ERR_PROJECT_UNKNOWN)))

;; Core operations
(define-public (register-carbon-project 
    (project_code (string-ascii 255))
    (carbon_certificate (string-ascii 50)))
    (let (
        (current_timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
        (required_bond (* MINIMUM_AUDITOR_BOND (var-get global_compliance_standard)))
        (validated_project_code (unwrap! (validate-project-code project_code) ERR_MALFORMED_PROJECT_CODE))
        (validated_certificate (unwrap! (validate-emission-certificate carbon_certificate) ERR_INVALID_EMISSION_DATA)))
        
        ;; Access control and system checks
        (asserts! (is-eq tx-sender (var-get platform_coordinator)) ERR_ACCESS_DENIED)
        (asserts! (not (var-get platform_maintenance_mode)) ERR_PLATFORM_OFFLINE)
        (asserts! (>= (stx-get-balance tx-sender) required_bond) ERR_INSUFFICIENT_BONDS)
        
        ;; Check for duplicate project - using validated project code
        (asserts! (is-none (map-get? registered_carbon_projects {project_code: validated_project_code})) 
                  ERR_PROJECT_DUPLICATE)
        
        ;; Transfer bond and register project
        (try! (stx-transfer? required_bond tx-sender (as-contract tx-sender)))
        (map-set registered_carbon_projects
            {project_code: validated_project_code}
            {
                project_developer: tx-sender,
                compliance_tier: "certified",
                registration_timestamp: current_timestamp,
                greenwashing_risk_score: u0,
                total_fraud_allegations: u0,
                auditor_bond_locked: required_bond,
                last_impact_assessment: current_timestamp,
                carbon_certificate: validated_certificate
            })
        (ok true)))

(define-public (submit-fraud-allegation 
    (project_code (string-ascii 255)) 
    (impact_evidence (string-ascii 500))
    (fraud_likelihood uint))
    (let (
        (current_timestamp (unwrap-panic (get-block-info? time (- block-height u1))))
        (auditor_record (unwrap! (map-get? carbon_auditor_registry {auditor_address: tx-sender}) 
                                ERR_INVALID_AUDITOR_CREDENTIALS))
        (validated_project_code (unwrap! (validate-project-code project_code) ERR_MALFORMED_PROJECT_CODE))
        (validated_evidence (unwrap! (validate-impact-documentation impact_evidence) ERR_INSUFFICIENT_DOCUMENTATION))
        (validated_likelihood (unwrap! (validate-carbon-efficiency fraud_likelihood) ERR_INVALID_CARBON_RATING))
        (project_exists (is-some (map-get? registered_carbon_projects {project_code: validated_project_code}))))
        
        ;; System checks
        (asserts! (not (var-get platform_maintenance_mode)) ERR_PLATFORM_OFFLINE)
        (asserts! project_exists ERR_PROJECT_UNKNOWN)
        (asserts! (>= (get professional_rating auditor_record) REQUIRED_AUDITOR_CERTIFICATION) 
                  ERR_INVALID_AUDITOR_CREDENTIALS)
        (asserts! (> (- current_timestamp (get last_audit_timestamp auditor_record)) ASSESSMENT_INTERVAL_SECONDS) 
                  ERR_ASSESSMENT_LOCKOUT)
        
        ;; Record fraud allegation
        (map-set fraud_allegation_cases
            {project_code: validated_project_code}
            {
                whistleblower_address: tx-sender,
                allegation_timestamp: current_timestamp,
                impact_evidence: validated_evidence,
                case_status: "investigating",
                fraud_likelihood: validated_likelihood,
                stakeholder_count: u1
            })
        
        ;; Update auditor assignment record
        (map-set auditor_project_assignments
            {auditor_address: tx-sender, assigned_project: validated_project_code}
            {
                assessment_count: u1,
                last_assessment_date: current_timestamp,
                auditor_credibility: (get professional_rating auditor_record),
                bonded_capital: (get bonded_tokens auditor_record),
                validated_assessments: u0
            })
        
        ;; Update project fraud count
        (match (map-get? registered_carbon_projects {project_code: validated_project_code})
            project_details 
                (map-set registered_carbon_projects
                    {project_code: validated_project_code}
                    (merge project_details {
                        total_fraud_allegations: (+ (get total_fraud_allegations project_details) u1)
                    }))
            false)
        (ok true)))

(define-private (update-project-risk-assessment (project_code (string-ascii 255)) (risk_delta int))
    (let ((validated_project_code (unwrap! (validate-project-code project_code) ERR_MALFORMED_PROJECT_CODE)))
        (match (map-get? registered_carbon_projects {project_code: validated_project_code})
            project_details 
                (begin
                    (let ((current_risk (get greenwashing_risk_score project_details))
                          (new_risk (if (> risk_delta 0) 
                                      (+ current_risk (to-uint risk_delta))
                                      (if (>= current_risk (to-uint (- 0 risk_delta)))
                                        (- current_risk (to-uint (- 0 risk_delta)))
                                        u0))))
                        (map-set registered_carbon_projects
                            {project_code: validated_project_code}
                            (merge project_details {
                                greenwashing_risk_score: new_risk
                            }))
                        (ok true)))
            ERR_PROJECT_UNKNOWN)))
