# Security policy

Please report security problems privately through GitHub's **Report a vulnerability** button (Security tab), not in a public issue. Include steps to reproduce and the version (`(Get-ADTConfig).Version`).

The toolkit runs with the rights of the person using it. It never stores credentials, and it writes generated passwords to disk only when asked to (`-IncludePasswordsInReport`, or **Save passwords...** in the app).
