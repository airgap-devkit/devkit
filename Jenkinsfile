// =============================================================================
// AirGap DevKit — Jenkins Declarative Pipeline
// See ci/jenkins/SETUP.md for full setup instructions and parameter reference.
// Requires: Pipeline Utility Steps plugin, Credentials Binding plugin,
//           AnsiColor plugin (optional), linux + windows agent labels.
// =============================================================================
pipeline {
    agent none

    parameters {
        // ── Identity ──────────────────────────────────────────────────────────
        string(
            name:         'TEAM_NAME',
            defaultValue: 'My Team',
            description:  'Team display name written to devkit.config.json and pushed to the running server.'
        )
        string(
            name:         'ORG_NAME',
            defaultValue: '',
            description:  'Organization name (leave blank to keep existing value).'
        )
        string(
            name:         'DEVKIT_NAME',
            defaultValue: 'AirGap DevKit',
            description:  'UI title shown in the dashboard header.'
        )

        // ── Install ───────────────────────────────────────────────────────────
        choice(
            name:    'PROFILE',
            choices: ['minimal', 'cpp-dev', 'devops', 'full'],
            description: '''Install profile:
  minimal  — core tools only (clang, cmake, python, style-formatter)
  cpp-dev  — full C++ developer stack
  devops   — infrastructure and automation tools
  full     — every available tool'''
        )
        choice(
            name:    'TARGET_OS',
            choices: ['linux', 'windows', 'both'],
            description: 'Which platform agent(s) to install on. Requires matching Jenkins agent labels.'
        )
        string(
            name:         'SERVER_HOST',
            defaultValue: '127.0.0.1',
            description:  'Bind address the devkit server listens on (used for API health checks in the Server stage).'
        )
        string(
            name:         'SERVER_PORT',
            defaultValue: '9090',
            description:  'Port for the devkit server.'
        )
        booleanParam(
            name:         'ADMIN_INSTALL',
            defaultValue: false,
            description:  'Pass --admin to install-cli.sh. Installs system-wide. Requires a privileged agent.'
        )

        // ── Package Upload ────────────────────────────────────────────────────
        booleanParam(
            name:         'UPLOAD_PACKAGE',
            defaultValue: false,
            description:  'Upload a .zip package bundle to the running devkit server via POST /packages/upload.'
        )
        string(
            name:         'PACKAGE_FILE_PATH',
            defaultValue: '',
            description:  'Absolute path on the Linux agent to the .zip package file. Required when UPLOAD_PACKAGE=true.'
        )

        // ── Team Config ───────────────────────────────────────────────────────
        booleanParam(
            name:         'EXPORT_TEAM_CONFIG',
            defaultValue: false,
            description:  'Call GET /api/export and save the result as a build artifact (team-config-export.json).'
        )
        text(
            name:         'IMPORT_TEAM_CONFIG',
            defaultValue: '',
            description:  'Raw JSON to POST to /api/import. Paste team-config.json contents here. Leave blank to skip.'
        )

        // ── Custom Profile ────────────────────────────────────────────────────
        text(
            name:         'SAVE_PROFILE_JSON',
            defaultValue: '',
            description:  'JSON for POST /api/profiles — creates or updates a custom profile. Example:\n{"id":"my-team","name":"My Team","description":"Custom tool set","tool_ids":["cmake","python","git"],"color":"blue"}'
        )

        // ── Tests ─────────────────────────────────────────────────────────────
        booleanParam(
            name:         'RUN_VALIDATE',
            defaultValue: true,
            description:  'Run tests/validate-manifests.sh (JSON syntax + required fields check) before install.'
        )
        booleanParam(
            name:         'RUN_SMOKE_TESTS',
            defaultValue: true,
            description:  'Run tests/run-tests.sh after install to verify all profile tools are functional.'
        )

        // ── Atlassian ─────────────────────────────────────────────────────────
        booleanParam(
            name:         'ATLASSIAN_UPDATE',
            defaultValue: false,
            description:  'Push build status and tool inventory to Jira and/or Confluence. Requires ATLASSIAN_* credentials.'
        )
        string(
            name:         'JIRA_ISSUE_KEY',
            defaultValue: '',
            description:  'Jira issue to comment on (e.g. DEVKIT-42). Leave blank to skip Jira. Requires ATLASSIAN_UPDATE=true.'
        )
        string(
            name:         'CONFLUENCE_PAGE_ID',
            defaultValue: '',
            description:  'Confluence page ID to overwrite with status table. Leave blank to skip Confluence. Requires ATLASSIAN_UPDATE=true.'
        )
    }

    options {
        timestamps()
        timeout(time: 2, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '10'))
        skipDefaultCheckout()
    }

    // =========================================================================
    stages {

        // ── 1. Validate ───────────────────────────────────────────────────────
        stage('Validate Manifests') {
            when { expression { return params.RUN_VALIDATE } }
            agent { label 'linux' }
            steps {
                checkout scm
                sh 'bash tests/validate-manifests.sh --verbose'
            }
        }

        // ── 2. Configure ──────────────────────────────────────────────────────
        // Patches devkit.config.json with pipeline parameters and stashes it so
        // downstream stages on any agent pick up the same config.
        stage('Configure') {
            agent { label 'linux' }
            steps {
                checkout scm
                script {
                    def cfg = readJSON file: 'devkit.config.json'
                    if (params.TEAM_NAME?.trim())   cfg.team_name       = params.TEAM_NAME.trim()
                    if (params.ORG_NAME != null)    cfg.org_name        = params.ORG_NAME.trim()
                    if (params.DEVKIT_NAME?.trim()) cfg.devkit_name     = params.DEVKIT_NAME.trim()
                    cfg.hostname        = params.SERVER_HOST
                    cfg.port            = params.SERVER_PORT.toInteger()
                    cfg.default_profile = params.PROFILE
                    writeJSON file: 'devkit.config.json', json: cfg, pretty: 2
                    echo "devkit.config.json configured: team=${cfg.team_name}, profile=${cfg.default_profile}, port=${cfg.port}"
                }
                stash name: 'devkit-config', includes: 'devkit.config.json'
            }
        }

        // ── 3. Install ────────────────────────────────────────────────────────
        stage('Install') {
            parallel {
                stage('Install — Linux') {
                    when {
                        expression { return params.TARGET_OS == 'linux' || params.TARGET_OS == 'both' }
                    }
                    agent { label 'linux' }
                    steps {
                        checkout scm
                        unstash 'devkit-config'
                        sh """
                            FLAGS="--yes --profile ${params.PROFILE}"
                            [ '${params.ADMIN_INSTALL}' = 'true' ] && FLAGS="\$FLAGS --admin"
                            bash scripts/install-cli.sh \$FLAGS
                        """
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: '**/INSTALL_RECEIPT.txt', allowEmptyArchive: true
                        }
                    }
                }

                stage('Install — Windows') {
                    when {
                        expression { return params.TARGET_OS == 'windows' || params.TARGET_OS == 'both' }
                    }
                    agent { label 'windows' }
                    steps {
                        checkout scm
                        unstash 'devkit-config'
                        bat "bash scripts/install-cli.sh --yes --profile ${params.PROFILE}"
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: '**/INSTALL_RECEIPT.txt', allowEmptyArchive: true
                        }
                    }
                }
            }
        }

        // ── 4. Server Operations ──────────────────────────────────────────────
        // Start the devkit server on Linux, exercise the API (config push,
        // optional package upload / profile save / team import / export),
        // collect health snapshot, then cleanly stop the server.
        stage('Server Operations') {
            agent { label 'linux' }
            steps {
                checkout scm
                unstash 'devkit-config'

                // Start server
                sh """
                    nohup bash scripts/launch.sh --no-browser > devkit-server.log 2>&1 &
                    echo \$! > .server.pid

                    echo "Waiting for server at http://${params.SERVER_HOST}:${params.SERVER_PORT}/health ..."
                    for i in \$(seq 1 30); do
                        if curl -sf "http://${params.SERVER_HOST}:${params.SERVER_PORT}/health" >/dev/null 2>&1; then
                            echo "Server ready (attempt \$i)"
                            break
                        fi
                        sleep 2
                        if [ "\$i" -eq 30 ]; then
                            echo "ERROR: server did not start within 60s"
                            cat devkit-server.log
                            exit 1
                        fi
                    done
                """

                // Read auth token written by the server on first start
                script {
                    env.DEVKIT_TOKEN = sh(returnStdout: true, script: 'cat .devkit-token 2>/dev/null || echo ""').trim()
                }

                // Push team identity to running server
                script {
                    writeJSON file: '/tmp/dk-config.json', json: [
                        team_name:   params.TEAM_NAME.trim(),
                        org_name:    params.ORG_NAME.trim(),
                        devkit_name: params.DEVKIT_NAME.trim()
                    ]
                }
                sh """
                    curl -sf -X POST \
                         -H 'Content-Type: application/json' \
                         -H "X-DevKit-Token: ${env.DEVKIT_TOKEN}" \
                         -d @/tmp/dk-config.json \
                         "http://${params.SERVER_HOST}:${params.SERVER_PORT}/api/config"
                    echo "Team identity pushed"
                """

                // Upload package bundle (optional)
                script {
                    if (params.UPLOAD_PACKAGE) {
                        if (!params.PACKAGE_FILE_PATH?.trim()) {
                            error('UPLOAD_PACKAGE=true but PACKAGE_FILE_PATH is empty')
                        }
                        sh """
                            [ -f '${params.PACKAGE_FILE_PATH}' ] || \
                                { echo "ERROR: '${params.PACKAGE_FILE_PATH}' not found"; exit 1; }
                            curl -sf -X POST \
                                 -H "X-DevKit-Token: ${env.DEVKIT_TOKEN}" \
                                 -F 'package=@${params.PACKAGE_FILE_PATH}' \
                                 "http://${params.SERVER_HOST}:${params.SERVER_PORT}/packages/upload"
                            echo "Package uploaded: ${params.PACKAGE_FILE_PATH}"
                        """
                    }
                }

                // Create/update custom profile (optional)
                script {
                    if (params.SAVE_PROFILE_JSON?.trim()) {
                        writeFile file: '/tmp/dk-profile.json', text: params.SAVE_PROFILE_JSON
                        sh """
                            curl -sf -X POST \
                                 -H 'Content-Type: application/json' \
                                 -H "X-DevKit-Token: ${env.DEVKIT_TOKEN}" \
                                 -d @/tmp/dk-profile.json \
                                 "http://${params.SERVER_HOST}:${params.SERVER_PORT}/api/profiles"
                            echo "Custom profile saved"
                        """
                    }
                }

                // Import team config (optional)
                script {
                    if (params.IMPORT_TEAM_CONFIG?.trim()) {
                        writeFile file: '/tmp/dk-import.json', text: params.IMPORT_TEAM_CONFIG
                        sh """
                            curl -sf -X POST \
                                 -H 'Content-Type: application/json' \
                                 -H "X-DevKit-Token: ${env.DEVKIT_TOKEN}" \
                                 -d @/tmp/dk-import.json \
                                 "http://${params.SERVER_HOST}:${params.SERVER_PORT}/api/import"
                            echo "Team config imported"
                        """
                    }
                }

                // Export team config (optional)
                script {
                    if (params.EXPORT_TEAM_CONFIG) {
                        sh """
                            curl -sf \
                                 -H "X-DevKit-Token: ${env.DEVKIT_TOKEN}" \
                                 "http://${params.SERVER_HOST}:${params.SERVER_PORT}/api/export" \
                                 -o team-config-export.json
                            echo "Team config exported"
                        """
                        archiveArtifacts artifacts: 'team-config-export.json'
                    }
                }

                // Tool health snapshot (always)
                sh """
                    curl -sf \
                         -H "X-DevKit-Token: ${env.DEVKIT_TOKEN}" \
                         "http://${params.SERVER_HOST}:${params.SERVER_PORT}/api/health/tools" \
                         -o tool-health.json
                    echo "Tool health:"
                    cat tool-health.json
                """
                archiveArtifacts artifacts: 'tool-health.json'
            }
            post {
                always {
                    sh '''
                        if [ -f .server.pid ]; then
                            kill "$(cat .server.pid)" 2>/dev/null || true
                            rm -f .server.pid
                        fi
                    '''
                    archiveArtifacts artifacts: 'devkit-server.log', allowEmptyArchive: true
                }
            }
        }

        // ── 5. Smoke Tests ────────────────────────────────────────────────────
        stage('Smoke Tests') {
            when { expression { return params.RUN_SMOKE_TESTS } }
            parallel {
                stage('Smoke Tests — Linux') {
                    when {
                        expression { return params.TARGET_OS == 'linux' || params.TARGET_OS == 'both' }
                    }
                    agent { label 'linux' }
                    steps {
                        checkout scm
                        sh 'bash tests/run-tests.sh --verbose'
                        sh 'bash tests/check-installed-tools.sh --verbose'
                    }
                }
                stage('Smoke Tests — Windows') {
                    when {
                        expression { return params.TARGET_OS == 'windows' || params.TARGET_OS == 'both' }
                    }
                    agent { label 'windows' }
                    steps {
                        checkout scm
                        bat 'bash tests/run-tests.sh --verbose'
                    }
                }
            }
        }

        // ── 6. Atlassian ──────────────────────────────────────────────────────
        stage('Atlassian') {
            when {
                allOf {
                    expression { return params.ATLASSIAN_UPDATE }
                    expression { return params.JIRA_ISSUE_KEY?.trim() || params.CONFLUENCE_PAGE_ID?.trim() }
                }
            }
            agent { label 'linux' }
            steps {
                checkout scm
                withCredentials([
                    string(credentialsId: 'ATLASSIAN_BASE_URL',   variable: 'ATLASSIAN_BASE_URL'),
                    string(credentialsId: 'ATLASSIAN_USER_EMAIL', variable: 'ATLASSIAN_USER_EMAIL'),
                    string(credentialsId: 'ATLASSIAN_API_TOKEN',  variable: 'ATLASSIAN_API_TOKEN')
                ]) {
                    script {
                        def result = currentBuild.currentResult
                        if (params.JIRA_ISSUE_KEY?.trim()) {
                            sh """
                                bash ci/atlassian/jira-update.sh \
                                    --issue   '${params.JIRA_ISSUE_KEY}' \
                                    --status  '${result}' \
                                    --url     '${env.BUILD_URL}' \
                                    --profile '${params.PROFILE}' \
                                    --team    '${params.TEAM_NAME}'
                            """
                        }
                        if (params.CONFLUENCE_PAGE_ID?.trim()) {
                            sh """
                                bash ci/atlassian/confluence-update.sh \
                                    --page-id '${params.CONFLUENCE_PAGE_ID}' \
                                    --status  '${result}' \
                                    --url     '${env.BUILD_URL}' \
                                    --profile '${params.PROFILE}' \
                                    --team    '${params.TEAM_NAME}' \
                                    --build   '${env.BUILD_NUMBER}'
                            """
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    post {
        success {
            echo "AirGap DevKit pipeline PASSED | profile=${params.PROFILE} | os=${params.TARGET_OS} | team=${params.TEAM_NAME}"
        }
        failure {
            echo "AirGap DevKit pipeline FAILED — review stage logs above"
        }
        always {
            node('linux') {
                sh 'rm -f /tmp/dk-config.json /tmp/dk-profile.json /tmp/dk-import.json 2>/dev/null || true'
            }
        }
    }
}
