# Security Policy

## Reporting a Vulnerability

If you find a security vulnerability or any other issue, please report it to me.
The best place to do so is the GitHub issues page:

**[Report a vulnerability or issue here](https://github.com/SigKdev/godot-gitot/issues)**

Please include as much detail as possible:
A description of the problem, how to reproduce it, and any suggestions you have.
I appreciate you taking the time to help make this project better, and I'll do my best to fix things as quickly as I can.

**Thank you!**

---

## GitHub Personal Access Token

Only needed to use the **GitHub Issues Tracker Board** feature.

> [!CAUTION]
> 
> **Gitot** stores your GitHub PAT locally in plaintext at `user://gitot_auth.cfg` (outside `res://`, so it is never committed to
> your repository).
> 
> **This is not encrypted.** Godot/GDScript cannot access your OS-level credential store (Windows Credential Manager, macOS
> Keychain, etc.) without a native extension, which is outside this plugin's scope. **Anyone with access to your local user
> account can read this file.** And the Godot hot-reload and `_exit_tree()` make it not possible to auto clear the PAT when
> uninstalling/disabling Gitot. **You must click "Clear Token" before uninstalling/disabling**

> [!TIP]
> 
> **PAT Recommendations:**
> 
> - Use a **fine-grained token** scoped to Repo Access and with Issues Access read/write only. **Never an admin or org-wide
> token!** - Use the **Clear Token** button in the Gitot Issues Panel toolbar **before uninstalling or disabling the plugin**, or
> when working on a shared machine! - If you do not intent to use this feature, opt-out in settings to unload it completely! -
> Read the GitHub Personal Access Token
> [documentation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
