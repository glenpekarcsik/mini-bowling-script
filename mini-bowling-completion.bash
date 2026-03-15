#!/usr/bin/env bash
# =============================================================================
#  mini-bowling-completion.bash — bash tab completion for mini-bowling.sh
#
#  Install (pick one):
#
#  System-wide (recommended — works for all users and cron):
#    sudo cp mini-bowling-completion.bash /etc/bash_completion.d/mini-bowling.sh
#
#  Current user only:
#    cp mini-bowling-completion.bash ~/.local/share/bash-completion/completions/mini-bowling.sh
#    # Then add to ~/.bashrc if not auto-loaded:
#    # source ~/.local/share/bash-completion/completions/mini-bowling.sh
#
#  Or source directly from ~/.bashrc for immediate use:
#    echo 'source /path/to/mini-bowling-completion.bash' >> ~/.bashrc
#    source ~/.bashrc
#
#  Reload without rebooting:
#    source /etc/bash_completion.d/mini-bowling.sh
# =============================================================================

_mini_bowling_complete() {
    local cur prev words cword
    _init_completion || return

    # ── Top-level commands ────────────────────────────────────────────────────
    local commands="
        status version install preflight doctor
        deploy upload update check-update rollback
        download check-scoremore-update scoremore-version
        scoremore-history rollback-scoremore start-scoremore
        setup-autostart remove-autostart
        watchdog setup-watchdog
        schedule-deploy unschedule-deploy
        serial-log console list
        logs update-script backup disk-cleanup
        wait-for-network create-dir install-cli
        pi-status pi-update pi-reboot pi-shutdown
        wifi-status vnc-status vnc-setup
        restart repair ports info tail-all test-upload scoremore-logs
    "

    # ── Completion for second word (subcommands / flags) ──────────────────────
    case "$prev" in

        mini-bowling.sh|mini-bowling)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            return 0
            ;;

        logs)
            COMPREPLY=( $(compgen -W "list follow dump tail clean" -- "$cur") )
            return 0
            ;;

        serial-log)
            COMPREPLY=( $(compgen -W "start stop status tail" -- "$cur") )
            return 0
            ;;

        scoremore-history)
            COMPREPLY=( $(compgen -W "list use clean" -- "$cur") )
            return 0
            ;;

        setup-watchdog)
            COMPREPLY=( $(compgen -W "enable disable status" -- "$cur") )
            return 0
            ;;

        vnc-setup)
            COMPREPLY=( $(compgen -W "start stop enable-autostart disable-autostart" -- "$cur") )
            return 0
            ;;

        scoremore-logs)
            COMPREPLY=( $(compgen -W "show list tail dump" -- "$cur") )
            return 0
            ;;

        test-upload)
            # Offer sketch folder names
            local sketches=""
            local script_path
            script_path=$(command -v mini-bowling.sh 2>/dev/null)
            if [[ -n "$script_path" ]]; then
                local project_dir
                project_dir=$(grep -m1 'PROJECT_DIR=' "$script_path" 2>/dev/null | \
                    sed 's/.*PROJECT_DIR="\(.*\)"/\1/' | \
                    sed "s|\$HOME|$HOME|g" | sed "s|~|$HOME|g" || true)
                if [[ -n "$project_dir" && -d "$project_dir" ]]; then
                    sketches=$(find "$project_dir" -mindepth 1 -maxdepth 1 -type d \
                        ! -name '.*' ! -name 'build' ! -name 'cache' ! -name 'libraries' \
                        -printf '--%f\n' 2>/dev/null | sort)
                fi
            fi
            COMPREPLY=( $(compgen -W "$sketches" -- "$cur") )
            return 0
            ;;

        status)
            COMPREPLY=( $(compgen -W "--watch -w" -- "$cur") )
            return 0
            ;;

        tail-all)
            COMPREPLY=( $(compgen -W "50 100 200" -- "$cur") )
            return 0
            ;;

        upload)
            # Offer --list-sketches, --no-kill, --branch, plus any sketch folders
            local sketches=""
            local script_path
            script_path=$(command -v mini-bowling.sh 2>/dev/null)
            if [[ -n "$script_path" ]]; then
                local project_dir
                project_dir=$(grep -m1 'PROJECT_DIR=' "$script_path" 2>/dev/null | \
                    sed 's/.*PROJECT_DIR="\(.*\)"/\1/' | \
                    sed "s|\$HOME|$HOME|g" | \
                    sed "s|~|$HOME|g" || true)
                if [[ -n "$project_dir" && -d "$project_dir" ]]; then
                    sketches=$(find "$project_dir" -mindepth 1 -maxdepth 1 -type d \
                        ! -name '.*' ! -name 'build' ! -name 'cache' ! -name 'libraries' \
                        -printf '--%f\n' 2>/dev/null | sort)
                fi
            fi
            COMPREPLY=( $(compgen -W "--list-sketches --no-kill --branch $sketches" -- "$cur") )
            return 0
            ;;

        rollback)
            # Suggest common step counts
            COMPREPLY=( $(compgen -W "1 2 3" -- "$cur") )
            return 0
            ;;

        download)
            COMPREPLY=( $(compgen -W "latest" -- "$cur") )
            return 0
            ;;

        backup)
            COMPREPLY=( $(compgen -W "--include-appimage" -- "$cur") )
            return 0
            ;;

        preflight)
            COMPREPLY=( $(compgen -W "--quick -q" -- "$cur") )
            return 0
            ;;

        schedule-deploy)
            # Suggest common deploy times
            COMPREPLY=( $(compgen -W "02:00 02:30 03:00 03:30 04:00" -- "$cur") )
            return 0
            ;;

        wait-for-network)
            # Suggest common timeout values
            COMPREPLY=( $(compgen -W "30 60 120" -- "$cur") )
            return 0
            ;;

        logs)
            COMPREPLY=( $(compgen -W "list follow dump tail clean" -- "$cur") )
            return 0
            ;;

        scoremore-history)
            COMPREPLY=( $(compgen -W "list use clean" -- "$cur") )
            return 0
            ;;
    esac

    # ── Completion for third word (flags after subcommands) ───────────────────
    if [[ ${#words[@]} -ge 3 ]]; then
        local cmd="${words[1]}"
        local subcmd="${words[2]}"

        case "$cmd" in
            logs)
                case "$subcmd" in
                    clean)
                        COMPREPLY=( $(compgen -W "--keep" -- "$cur") )
                        return 0
                        ;;
                    tail)
                        COMPREPLY=( $(compgen -W "50 100 200 --date" -- "$cur") )
                        return 0
                        ;;
                    dump)
                        COMPREPLY=( $(compgen -W "--date" -- "$cur") )
                        return 0
                        ;;
                esac
                ;;
            deploy)
                case "$subcmd" in
                    --branch)
                        # Suggest git branches if available
                        local project_dir=""
                        local script_path
                        script_path=$(command -v mini-bowling.sh 2>/dev/null)
                        if [[ -n "$script_path" ]]; then
                            project_dir=$(grep -m1 'PROJECT_DIR=' "$script_path" 2>/dev/null | \
                                sed 's/.*PROJECT_DIR="\(.*\)"/\1/' | \
                                sed "s|\$HOME|$HOME|g" | sed "s|~|$HOME|g" || true)
                        fi
                        if [[ -n "$project_dir" && -d "$project_dir/.git" ]]; then
                            local branches
                            branches=$(git -C "$project_dir" branch -a 2>/dev/null | \
                                sed 's|.*remotes/origin/||;s|^\*\? *||' | grep -v HEAD | sort -u)
                            COMPREPLY=( $(compgen -W "$branches" -- "$cur") )
                        else
                            COMPREPLY=( $(compgen -W "main master" -- "$cur") )
                        fi
                        return 0
                        ;;
                esac
                ;;
            scoremore-history)
                case "$subcmd" in
                    use)
                        # List available AppImage versions
                        local script_path
                        script_path=$(command -v mini-bowling.sh 2>/dev/null)
                        local sm_dir=""
                        if [[ -n "$script_path" ]]; then
                            sm_dir=$(grep -m1 'SCOREMORE_DIR=' "$script_path" 2>/dev/null | \
                                sed 's/.*SCOREMORE_DIR="\(.*\)"/\1/' | \
                                sed "s|\$HOME|$HOME|g" | sed "s|~|$HOME|g" || true)
                        fi
                        if [[ -n "$sm_dir" && -d "$sm_dir" ]]; then
                            local versions
                            versions=$(find "$sm_dir" -maxdepth 1 -name 'ScoreMore-*.AppImage' \
                                -printf '%f\n' 2>/dev/null | \
                                sed 's/^ScoreMore-//;s/-arm64\.AppImage$//' | sort -V -r)
                            COMPREPLY=( $(compgen -W "$versions" -- "$cur") )
                        fi
                        return 0
                        ;;
                esac
                ;;
        esac
    fi

    # Default: complete top-level commands if nothing matched
    if [[ "$cword" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
    fi

    return 0
}

complete -F _mini_bowling_complete mini-bowling.sh
complete -F _mini_bowling_complete mini-bowling
