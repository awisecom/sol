# Installed by sol (steps/10-system.sh).
# macOS Terminal forwards LC_CTYPE=UTF-8 over SSH. That isn't a locale name on
# Linux, so bash and perl warn on every login. Fall back to the system locale.
if [ "${LC_CTYPE:-}" = "UTF-8" ]; then
  unset LC_CTYPE
fi
