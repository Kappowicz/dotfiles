#!/usr/bin/env python3
import sys
import json
import os
import pwd

REAL_HOME = os.environ.get("LIMITS_HOME", pwd.getpwuid(os.getuid()).pw_dir)
PROFILE_HOME = os.path.expanduser("~")
PROFILE_NAME = {".agy-profile2": "agy2", ".agy-profile3": "agy3"}.get(os.path.basename(PROFILE_HOME), "agy")
CACHE_DIR = os.path.join(REAL_HOME, ".cache", "agent_limits")

def format_tokens(num):
    if num is None:
        return "0"
    num = float(num)
    if num >= 1_000_000:
        return f"{num / 1_000_000:.1f}M"
    if num >= 1_000:
        return f"{num / 1_000:.1f}k"
    return str(int(num))

def format_duration(seconds):
    if seconds is None or seconds < 0:
        return ""
    seconds = int(seconds)
    days = seconds // 86400
    hours = (seconds % 86400) // 3600
    minutes = (seconds % 3600) // 60
    if days > 0:
        return f"{days}d {hours}h"
    if hours > 0:
        return f"{hours}h {minutes}m"
    if minutes > 0:
        return f"{minutes}m"
    return f"{seconds}s"

def color_percent(pct):
    if pct is None:
        return "\033[90m--%\033[0m"
    val = float(pct)
    if val < 60:
        color = "\033[32m"  # Green
    elif val < 85:
        color = "\033[33m"  # Yellow
    else:
        color = "\033[31m"  # Red
    return f"{color}{val:.1f}%\033[0m"

def main():
    try:
        raw_input = sys.stdin.read()
        if not raw_input.strip():
            return
        data = json.loads(raw_input)
        try:
            email = data.get("email")
            if email and "quota" in data:
                import os
                os.makedirs(CACHE_DIR, exist_ok=True)
                with open(os.path.join(CACHE_DIR, f"{PROFILE_NAME}.json"), "w") as f_cache:
                    json.dump(data, f_cache)
        except Exception:
            pass
    except Exception:
        return

    try:
        parts = []
        quotas = data.get("quota") or {}
        model_info = data.get("model") or {}
        model_id = (model_info.get("id") or "").lower()

        # Quota selection (Gemini vs Argon vs 3rd party)
        is_3p = ("claude" in model_id or "gpt" in model_id or "openai" in model_id)
        is_argon = "argon" in model_id
        pref_5h = "3p-5h" if is_3p and "3p-5h" in quotas else "gemini-5h"
        if is_3p and "3p-weekly" in quotas:
            pref_weekly = "3p-weekly"
        elif is_argon and "gemini-argon-wtu-weekly" in quotas:
            pref_weekly = "gemini-argon-wtu-weekly"
        else:
            pref_weekly = "gemini-weekly"

        q_5h = quotas.get(pref_5h) or quotas.get("5h") or quotas.get("gemini-5h") or quotas.get("3p-5h")
        q_weekly = quotas.get(pref_weekly) or quotas.get("weekly") or quotas.get("gemini-weekly") or quotas.get("3p-weekly")

        # 5h quota
        if q_5h:
            rem_frac = q_5h.get("remaining_fraction")
            used_pct = (1.0 - rem_frac) * 100 if rem_frac is not None else None
            reset_sec = q_5h.get("reset_in_seconds")
            reset_str = f" \033[90m({format_duration(reset_sec)})\033[0m" if reset_sec else ""
            parts.append(f"\033[1;37m5h:\033[0m {color_percent(used_pct)}{reset_str}")

        # 7d / weekly quota
        if q_weekly:
            rem_frac = q_weekly.get("remaining_fraction")
            used_pct = (1.0 - rem_frac) * 100 if rem_frac is not None else None
            reset_sec = q_weekly.get("reset_in_seconds")
            reset_str = f" \033[90m({format_duration(reset_sec)})\033[0m" if reset_sec else ""
            lbl_weekly = "7d (Argon):" if pref_weekly == "gemini-argon-wtu-weekly" else "7d:"
            parts.append(f"\033[1;37m{lbl_weekly}\033[0m {color_percent(used_pct)}{reset_str}")

        # Context window usage
        ctx = data.get("context_window") or {}
        total_in = ctx.get("total_input_tokens", 0) or 0
        total_out = ctx.get("total_output_tokens", 0) or 0
        tokens_used = total_in + total_out
        size = ctx.get("context_window_size", 0) or 0

        # Compute accurate percentage directly from tokens if available
        if size > 0 and tokens_used > 0:
            ctx_pct = (tokens_used / size) * 100.0
            ctx_detail = f" \033[90m({format_tokens(tokens_used)}/{format_tokens(size)})\033[0m"
        elif ctx.get("used_percentage") is not None:
            ctx_pct = float(ctx["used_percentage"])
            ctx_detail = f" \033[90m(0/{format_tokens(size)})\033[0m" if size > 0 else ""
        else:
            ctx_pct = 0.0
            ctx_detail = ""

        parts.append(f"\033[1;37mCtx:\033[0m {color_percent(ctx_pct)}{ctx_detail}")

        if parts:
            sep = " \033[90m│\033[0m "
            print(sep.join(parts))
    except Exception:
        pass

if __name__ == "__main__":
    main()
