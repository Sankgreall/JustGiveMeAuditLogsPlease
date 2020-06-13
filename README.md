# JustGiveMeAuditLogsPlease

For years, incident responders have looked up at the sky and dreamed of a world where pulling Office365 audit logs would be simple and efficient. Microsoft have really tried to make it difficult, but **JustGiveMeAuditLogsPlease** finally makes a seamless tenant-wide collection of the Unified Audit Logs possible.

## Is this just Hawk?

This is a fork of [Hawk](https://github.com/Canthv0/hawk), but it has been stripped down, re-designed, and massively optimised to do one thing: pull audit logs.

An amazing amount of credit still goes to Hawk's creators, and it remains a fantastic tool. However, it had severe limitations when dealing with audit logs, including:

- Collected data was stored in-memory until the end. The slightest error would destroy information that had taken hours to collect. 
- It was beholden to Microsoft's 50,000 record limit, making it useless for an entire tenant-wide collection.
- Record data was transformed into structured CSV, removing critical contextual information.
- EXO tokens would routinely expire mid-collection, leading to a fatal error (causing data loss).

In contract, **JustGiveMeAuditLogsPlease** has been designed by incident responders for incident responders. It features:

- Collection for more than 50,000 records. This is achieved by opting for a collection model that dynamically allocates chunks of time prior to calling `Search-UnifiedAuditLog`.
- No more interactive prompts. Just detail your `FilePath`parameter and press `Enter` for an immediate tenant-wide collection.
- If there are fatal errors (which are very rare), it's simple to resume right from where you left off thanks to `StartDate` and `EndDate` command line parameters that are now accurate down to the second (Hawk would automatically round this to midnight, leading to duplication and wasted time). 
- On-the-fly renewal for EXO tokens, meaning no more token expiry mid-collection.
- Replacement of `Out-File` in favour of `StreamWriter`, shaving hours off the time it would have otherwise taken to write collected records to disk.
- Creative handling of some very strange errors unique to the `Search-UnifiedAuditLog` API. **JustGiveMeAuditLogsPlease** drastically increases your chances of success over running that command natively.

## How to use

To run **JustGiveMeAuditLogsPlease**, clone this repository and run the following commands in PowerShell:

``` powershell
 Import-Module -Name "{path}\Hawk.psd1"
 Get-HawkTenantAzureAuditLog -FilePath "{path}"
```

You'll immediately be asked to authenticate into your Office365 tenant, and a 90-day collection will begin automatically. Here is some information on parameters you can use with the `Get-HawkTenanyAzureAuditLog` command:

| Parameter  | Description                                                  |
| ---------- | ------------------------------------------------------------ |
| -StartDate | A string containing the date that you would like to start collection from, e.g., '01/23/2020 05:34:33' or '05/02/2020'. Please remember to use American date styles (dd/MM/yyyy).<br /><br />If, for whatever reason, **JustGiveMeAuditLogsPlease** stops during a collection and you would like to resume it, simply configure the StartDate to the last time period it started collecting records from. If you haven't changed your FilePath, data will just be appended to your previous collection attempt. <br /><br />If you don't specify the EndDate parameter, then the EndDate will automatically be set to the current day. |
| -EndDate   | A string containing the date that you would like to end collection, e.g., '01/23/2020 05:34:33' or '05/02/2020'. Please remember to use American date styles (dd/MM/yyyy). |
| -Lookback  | If you don't want to use dates, simply enter a number indicating the days you want to look back on, starting from today, e.g., a value of 10 will start collection from midnight 10 days ago. This option will take priority if StartDate or EndDate is specified. |
| -FilePath  | The path to where **JustGiveMeAuditLogsPlease** will store your collected audit data and its log. |

