function Invoke-WPFUIThread {
    <#

    .SYNOPSIS
        Creates and runs a task on the A-SYS_clark WPF UI thread.

    .PARAMETER ScriptBlock
        The scriptblock to invoke in the thread
    #>

    [CmdletBinding()]
    Param (
        $ScriptBlock
    )

    if ($PARAM_NOUI) {
        return;
    }

    $sync.form.Dispatcher.Invoke([action]$ScriptBlock)
}
