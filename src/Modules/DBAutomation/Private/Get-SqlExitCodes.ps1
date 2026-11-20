function Get-SqlExitCodes
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('SqlServer', 'SSMS', 'ReportServer')]
        [Products]
        $Product
    )

    $ExitCodes = @(
        @{
            Code = '0'
            resultString = 'Success'
        }
    )

    if ($Product -eq 'SSMS')
    {
        $ExitCodes += @(
            @{
                Code = '1856439871'
                resultString = 'SSMS is currently running. Please close any open instances of SSMS and run this installer again.'
            }
        )
    }

    if ($Product -in @('SqlServer', 'ReportServer', 'SSMS'))
    {
        $ExitCodes += @(
            @{
                #In our testing, Get-PendingReboot will catch and handle the reboot request.
                Code = '3010'
                resultString = 'Success; Reboot Required.'
            }
        )
    }

    if ($Product -eq 'SqlServer')
    {
        $ExitCodes += @(
            @{
                #This should not occur as we're validating the reboot status above.
                Code = '-2067919934'
                resultString = 'Not Installed. System is pending a reboot.'
            }
            @{
                Code = '-2068643838'
                resultString = 'No change required'
            }
            @{
                #This should not occur as we're validating the patch level above.
                Code = '-2042429437'
                resultString = 'Already installed or at a higher patch level.'
            }
        )
    }

    if ($Product -eq 'ReportServer')
    {
        $ExitCodes += @(
            @{
                #This should not occur as we're validating the patch level above.
                Code = '1626'
                resultString = 'A newer version of Reporting Services is installed.'
            }
            @{
                #This should not occur as we're validating the patch level above.
                Code = '87'
                resultString = 'Product is already installed.'
            }
        )
    }

    return $ExitCodes
}