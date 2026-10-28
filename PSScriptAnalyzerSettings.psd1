@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Status messages are written to the host on purpose: the console shows them in colour and
        # the GUI captures them from the information stream of its background runspace.
        'PSAvoidUsingWriteHost',
        # Passwords typed into the GUI or read from a bulk-user CSV have to become SecureStrings.
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        # Internal New-* helpers build objects in memory; every public command that changes AD or
        # DNS supports -WhatIf/-Confirm, which tests/Toolkit.Tests.ps1 enforces.
        'PSUseShouldProcessForStateChangingFunctions',
        # The test stubs replace ActiveDirectory/DnsServer cmdlets globally.
        'PSAvoidGlobalVars'
    )
}
