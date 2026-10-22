<#
    FINE STUDIO BOOKING MANAGEMENT (WPF edition)
    Developed by Fine Software Hub  |  ofclsuleman@gmail.com  |  GitHub: ofclsuleman

    Run:   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\FineStudioBooking.ps1
    Data:  .\data\users.json and .\data\bookings.json (created automatically)
    Logo:  optional .\logo.png next to the script replaces the drawn logo
#>

# Resolve the application folder in both normal .ps1 mode and PS2EXE mode.
# In a compiled executable, $PSScriptRoot/$PSCommandPath can be empty.
$script:ExePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$script:IsCompiledExe = [string]::IsNullOrWhiteSpace($PSCommandPath)
if (-not $script:IsCompiledExe) {
    $script:AppRoot = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($PSCommandPath))
} else {
    $script:AppRoot = [System.IO.Path]::GetDirectoryName($script:ExePath)
}
if ([string]::IsNullOrWhiteSpace($script:AppRoot) -or -not [System.IO.Directory]::Exists($script:AppRoot)) {
    throw 'Could not determine the application folder. Please run the app from a normal local folder.'
}

# WPF requires STA. For a .ps1, relaunch PowerShell in STA if needed.
# For a compiled EXE, build with PS2EXE's -STA option instead of relaunching with an empty script path.
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    if (-not $script:IsCompiledExe -and -not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $PSCommandPath)) -WorkingDirectory $script:AppRoot
        exit
    } else {
        throw 'This EXE must be built with PS2EXE -STA enabled for WPF.'
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ============================================================
# Constants
# ============================================================
$script:AppName      = 'Fine Studio Booking Management'
$script:Inv          = [System.Globalization.CultureInfo]::InvariantCulture
$script:Dash         = [string][char]0x2014
$script:EnDash       = [string][char]0x2013
$script:Rule         = ([string][char]0x2500) * 15
$script:DefaultNote  = 'Payment must be cleared on the last working day of the event.'
$script:CustomLabel  = 'Custom (Manually Writeable)'

$script:EventOptions = @('Engagement', 'Nikah', 'Mehndi', 'Barat', 'Walima', 'Birthday', 'Mehfil', $script:CustomLabel)
$script:TimeOptions  = @('12:00 pm - 04:00 pm', '06:00 pm - 10:00 pm', $script:CustomLabel)

$script:EquipmentList = @(
    'DSLR Photo Camera', 'Sony Photo Camera', 'DSLR Video Camera', 'Sony Video Camera',
    'Cinematic Photo Camera', 'Cinematic Video Camera', 'Drone Camera', 'Custom'
)

$script:QtyBoxNames = @('TxtDelFilm', 'TxtDelPhotos', 'TxtDelRaw', 'TxtDelAlbum', 'TxtDelPrint', 'TxtDelUsb', 'TxtDelCustomQty')

# Keep .ps1 data alongside the script as before. A compiled EXE uses a writable
# per-user folder so installation under Program Files does not block saving.
if ($script:IsCompiledExe) {
    $script:DataDir = Join-Path $env:LOCALAPPDATA 'FineStudioBooking\data'
} else {
    $script:DataDir = Join-Path $script:AppRoot 'data'
}
if ([string]::IsNullOrWhiteSpace($script:DataDir)) {
    throw 'Could not determine a writable data folder.'
}
$script:UsersFile    = Join-Path $script:DataDir 'users.json'
$script:BookingsFile = Join-Path $script:DataDir 'bookings.json'
$script:SessionFile  = Join-Path $script:DataDir 'session.json'

# ============================================================
# Theme palettes (hex). Every key must exist in the XAML resources.
# ============================================================
$script:LightPalette = @{
    BgBrush        = '#F3F5FA'
    CardBrush      = '#FFFFFF'
    RowBrush       = '#F8FAFD'
    InputBrush     = '#FFFFFF'
    TextBrush      = '#1F2937'
    MutedBrush     = '#6B7280'
    LineBrush      = '#E2E8F0'
    AccentBrush    = '#4F46E5'
    OnAccentBrush  = '#FFFFFF'
    SidebarBrush   = '#FFFFFF'
    NavHoverBrush  = '#EEF3F8'
    NavActiveBrush = '#E9E7FF'
    GridBrush      = '#E6EAF2'
}
$script:DarkPalette = @{
    BgBrush        = '#0F1419'
    CardBrush      = '#171C24'
    RowBrush       = '#1C222C'
    InputBrush     = '#202733'
    TextBrush      = '#E5E7EB'
    MutedBrush     = '#9CA3AF'
    LineBrush      = '#2A3240'
    AccentBrush    = '#818CF8'
    OnAccentBrush  = '#FFFFFF'
    SidebarBrush   = '#12171F'
    NavHoverBrush  = '#1E2631'
    NavActiveBrush = '#29264B'
    GridBrush      = '#222A36'
}

# System colour keys (used by ComboBox popups) mapped to palette keys
$script:SysMap = @{
    WindowBrushKey           = 'InputBrush'
    ControlBrushKey          = 'InputBrush'
    ControlTextBrushKey      = 'TextBrush'
    WindowTextBrushKey       = 'TextBrush'
    HighlightBrushKey        = 'AccentBrush'
    HighlightTextBrushKey    = 'OnAccentBrush'
    ControlLightBrushKey     = 'LineBrush'
    ControlDarkBrushKey      = 'LineBrush'
    GrayTextBrushKey         = 'MutedBrush'
}

# ============================================================
# Runtime state
# ============================================================
$script:App           = $null
$script:Res           = $null
$script:Win           = $null
$script:CurrentUser   = $null
$script:EditingId     = $null
$script:DayRows       = New-Object System.Collections.ArrayList
$script:EquipGroups   = New-Object System.Collections.ArrayList
$script:PageMap       = @{}
$script:CurrentPage   = ''
$script:Swapping      = $false
$script:SwapOut       = $null
$script:SwapIn        = $null
$script:IsDark        = $false
# ============================================================
# XAML: theme resources, main window, dialog
# ============================================================

$script:ResourcesXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                    xmlns:sys="clr-namespace:System.Windows;assembly=PresentationFramework">

  <!-- Theme brushes (animated when the theme changes) -->
  <SolidColorBrush x:Key="BgBrush" Color="#F3F5FA"/>
  <SolidColorBrush x:Key="CardBrush" Color="#FFFFFF"/>
  <SolidColorBrush x:Key="RowBrush" Color="#F8FAFD"/>
  <SolidColorBrush x:Key="InputBrush" Color="#FFFFFF"/>
  <SolidColorBrush x:Key="TextBrush" Color="#1F2937"/>
  <SolidColorBrush x:Key="MutedBrush" Color="#6B7280"/>
  <SolidColorBrush x:Key="LineBrush" Color="#E2E8F0"/>
  <SolidColorBrush x:Key="AccentBrush" Color="#4F46E5"/>
  <SolidColorBrush x:Key="OnAccentBrush" Color="#FFFFFF"/>
  <SolidColorBrush x:Key="SidebarBrush" Color="#FFFFFF"/>
  <SolidColorBrush x:Key="NavHoverBrush" Color="#EEF3F8"/>
  <SolidColorBrush x:Key="NavActiveBrush" Color="#E9E7FF"/>
  <SolidColorBrush x:Key="GridBrush" Color="#E6EAF2"/>

  <!-- Static colours -->
  <SolidColorBrush x:Key="DangerBrush" Color="#DC2626"/>
  <LinearGradientBrush x:Key="HeaderGradient" StartPoint="0,0" EndPoint="1,1">
    <GradientStop Color="#0B5A70" Offset="0"/>
    <GradientStop Color="#14A3B8" Offset="1"/>
  </LinearGradientBrush>

  <!-- System colours, mapped to the theme so ComboBox popups follow dark/light mode -->
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.WindowBrushKey}" Color="#FFFFFF"/>
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.ControlBrushKey}" Color="#FFFFFF"/>
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.ControlTextBrushKey}" Color="#1F2937"/>
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.WindowTextBrushKey}" Color="#1F2937"/>
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.HighlightBrushKey}" Color="#4F46E5"/>
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.HighlightTextBrushKey}" Color="#FFFFFF"/>
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.ControlLightBrushKey}" Color="#E2E8F0"/>
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.ControlDarkBrushKey}" Color="#E2E8F0"/>
  <SolidColorBrush x:Key="{x:Static sys:SystemColors.GrayTextBrushKey}" Color="#6B7280"/>

  <!-- Text -->
  <Style TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="FontSize" Value="14"/>
  </Style>
  <Style x:Key="MutedText" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
  </Style>
  <Style x:Key="H1" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="FontSize" Value="26"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
  </Style>
  <Style x:Key="H2" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="FontSize" Value="17"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
  </Style>
  <Style x:Key="FieldLabel" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Margin" Value="0,0,0,6"/>
  </Style>
  <Style x:Key="StatValue" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="FontSize" Value="28"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
  </Style>

  <!-- Text inputs -->
  <Style TargetType="TextBox">
    <Setter Property="Background" Value="{DynamicResource InputBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="CaretBrush" Value="{DynamicResource TextBrush}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="12,0"/>
    <Setter Property="Height" Value="40"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="TextBox">
          <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
            <ScrollViewer x:Name="PART_ContentHost" Focusable="false" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsKeyboardFocused" Value="True">
              <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="Bd" Property="Opacity" Value="0.5"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="PasswordBox">
    <Setter Property="Background" Value="{DynamicResource InputBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="CaretBrush" Value="{DynamicResource TextBrush}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="12,0"/>
    <Setter Property="Height" Value="40"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="PasswordBox">
          <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10">
            <ScrollViewer x:Name="PART_ContentHost" Focusable="false" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsKeyboardFocused" Value="True">
              <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ComboBox">
    <Setter Property="Height" Value="40"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="Padding" Value="12,0,0,0"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="Background" Value="{DynamicResource InputBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  </Style>

  <Style TargetType="DatePicker">
    <Setter Property="Height" Value="40"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="Background" Value="{DynamicResource InputBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
  </Style>

  <!-- Buttons -->
  <Style x:Key="PrimaryButton" TargetType="Button">
    <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource OnAccentBrush}"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="Height" Value="44"/>
    <Setter Property="Padding" Value="20,0"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="Bd" Property="Opacity" Value="0.5"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
    <Setter Property="Background" Value="{DynamicResource InputBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
    <Setter Property="BorderThickness" Value="1"/>
  </Style>

  <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
    <Setter Property="Background" Value="{StaticResource DangerBrush}"/>
    <Setter Property="Foreground" Value="White"/>
  </Style>

  <Style x:Key="GhostButton" TargetType="Button">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="HorizontalContentAlignment" Value="Left"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="FontWeight" Value="Medium"/>
    <Setter Property="Height" Value="44"/>
    <Setter Property="Padding" Value="14,0"/>
    <Setter Property="Margin" Value="0,3,0,3"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="10" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource NavHoverBrush}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="Tag" Value="active">
        <Setter Property="Background" Value="{DynamicResource NavActiveBrush}"/>
        <Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/>
      </Trigger>
    </Style.Triggers>
  </Style>

  <Style x:Key="TitleButton" TargetType="Button">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Width" Value="46"/>
    <Setter Property="Height" Value="36"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Bd" Background="{TemplateBinding Background}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="{DynamicResource NavHoverBrush}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="CloseButton" TargetType="Button" BasedOn="{StaticResource TitleButton}">
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Bd" Background="{TemplateBinding Background}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Bd" Property="Background" Value="#E81123"/>
              <Setter Property="Foreground" Value="White"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- Wizard step pills -->
  <Style x:Key="StepPill" TargetType="Border">
    <Setter Property="CornerRadius" Value="20"/>
    <Setter Property="Padding" Value="16,7"/>
    <Setter Property="Margin" Value="6,0,0,0"/>
    <Setter Property="Background" Value="Transparent"/>
    <Style.Triggers>
      <Trigger Property="Tag" Value="active">
        <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
      </Trigger>
    </Style.Triggers>
  </Style>

  <!-- Data grid -->
  <Style x:Key="BookingsGrid" TargetType="DataGrid">
    <Setter Property="Background" Value="{DynamicResource CardBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="RowBackground" Value="{DynamicResource CardBrush}"/>
    <Setter Property="AlternatingRowBackground" Value="{DynamicResource RowBrush}"/>
    <Setter Property="HorizontalGridLinesBrush" Value="{DynamicResource GridBrush}"/>
    <Setter Property="VerticalGridLinesBrush" Value="Transparent"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="GridLinesVisibility" Value="Horizontal"/>
    <Setter Property="HeadersVisibility" Value="Column"/>
    <Setter Property="IsReadOnly" Value="True"/>
    <Setter Property="AutoGenerateColumns" Value="True"/>
    <Setter Property="CanUserAddRows" Value="False"/>
    <Setter Property="CanUserDeleteRows" Value="False"/>
    <Setter Property="SelectionMode" Value="Single"/>
    <Setter Property="SelectionUnit" Value="FullRow"/>
    <Setter Property="RowHeight" Value="46"/>
    <Setter Property="FontSize" Value="13"/>
  </Style>
  <Style TargetType="DataGridColumnHeader">
    <Setter Property="Background" Value="{DynamicResource InputBrush}"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Padding" Value="14,12"/>
    <Setter Property="BorderThickness" Value="0"/>
  </Style>
  <Style TargetType="DataGridCell">
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Padding" Value="14,0"/>
    <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    <Style.Triggers>
      <Trigger Property="IsSelected" Value="True">
        <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
        <Setter Property="Foreground" Value="{DynamicResource OnAccentBrush}"/>
      </Trigger>
    </Style.Triggers>
  </Style>
</ResourceDictionary>
'@

$script:MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Fine Studio Booking Management" Width="1240" Height="840"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize" MinWidth="900" MinHeight="650" MaxWidth="1920" MaxHeight="1200">
  <Border x:Name="Shell" Margin="14" CornerRadius="16" Background="{DynamicResource BgBrush}" ClipToBounds="True">
    <Border.Effect>
      <DropShadowEffect BlurRadius="20" ShadowDepth="0" Opacity="0.28" Color="#000000"/>
    </Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="40"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <!-- Title bar -->
      <Grid x:Name="TitleBar" Grid.Row="0" Background="Transparent">
        <TextBlock Text="Fine Studio Booking Management" Style="{StaticResource MutedText}" FontSize="12" VerticalAlignment="Center" Margin="20,0,0,0"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="BtnMin" Content="&#8211;" Style="{StaticResource TitleButton}"/>
          <Button x:Name="BtnClose" Content="&#10005;" Style="{StaticResource CloseButton}"/>
        </StackPanel>
      </Grid>

      <Grid Grid.Row="1">

        <!-- ================= LOGIN ================= -->
        <Grid x:Name="LoginView">
          <Grid.RenderTransform><TranslateTransform/></Grid.RenderTransform>
          <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Width="470">
            <Border x:Name="LoginLogoHost" Width="84" Height="84" CornerRadius="22" HorizontalAlignment="Center" Background="{StaticResource HeaderGradient}">
              <TextBlock Text="FS" Foreground="White" FontSize="30" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock Text="Fine Studio" FontSize="30" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,18,0,0"/>
            <TextBlock Text="Booking Management" FontSize="15" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center" Margin="0,2,0,26"/>

            <Border x:Name="LoginCard" Background="{DynamicResource CardBrush}" CornerRadius="18" Padding="30">
              <Border.RenderTransform><TranslateTransform/></Border.RenderTransform>
              <Border.Effect>
                <DropShadowEffect BlurRadius="16" ShadowDepth="1" Opacity="0.10"/>
              </Border.Effect>
              <StackPanel>
                <Grid Margin="0,0,0,24">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <Button x:Name="BtnTabLogin" Grid.Column="0" Content="Sign In" Style="{StaticResource GhostButton}" Tag="active" Margin="0,0,6,0" HorizontalContentAlignment="Center"/>
                  <Button x:Name="BtnTabSignup" Grid.Column="1" Content="Create Account" Style="{StaticResource GhostButton}" Margin="6,0,0,0" HorizontalContentAlignment="Center"/>
                </Grid>

                <StackPanel x:Name="PanelLogin">
                  <TextBlock Text="Registered user" Style="{StaticResource FieldLabel}"/>
                  <ComboBox x:Name="CboUser" DisplayMemberPath="FullName" Margin="0,0,0,18"/>
                  <TextBlock Text="Password" Style="{StaticResource FieldLabel}"/>
                  <PasswordBox x:Name="PwdLogin" Margin="0,0,0,24"/>
                  <Button x:Name="BtnLogin" Content="Sign In" Style="{StaticResource PrimaryButton}"/>
                  <Button x:Name="BtnDeleteUser" Content="Delete selected user" Style="{StaticResource DangerButton}" Margin="0,12,0,0"/>
                </StackPanel>

                <StackPanel x:Name="PanelSignup" Visibility="Collapsed">
                  <TextBlock Text="Studio name" Style="{StaticResource FieldLabel}"/>
                  <TextBox x:Name="TxtSuStudio" Margin="0,0,0,14"/>
                  <TextBlock Text="Full name" Style="{StaticResource FieldLabel}"/>
                  <TextBox x:Name="TxtSuFull" Margin="0,0,0,14"/>
                  <TextBlock Text="Contact number" Style="{StaticResource FieldLabel}"/>
                  <TextBox x:Name="TxtSuContact" Margin="0,0,0,14"/>
                  <TextBlock Text="Password (minimum 4 characters)" Style="{StaticResource FieldLabel}"/>
                  <PasswordBox x:Name="PwdSignup" Margin="0,0,0,24"/>
                  <Button x:Name="BtnSignup" Content="Create Account" Style="{StaticResource PrimaryButton}"/>
                </StackPanel>
              </StackPanel>
            </Border>
          </StackPanel>
        </Grid>

        <!-- ================= APP ================= -->
        <Grid x:Name="AppView" Visibility="Collapsed">
          <Grid.RenderTransform><TranslateTransform/></Grid.RenderTransform>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="252"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <!-- Sidebar -->
          <Border Grid.Column="0" Background="{DynamicResource SidebarBrush}" Padding="20,24,20,20">
            <DockPanel>
              <StackPanel DockPanel.Dock="Top">
                <StackPanel Orientation="Horizontal" Margin="0,0,0,34">
                  <Border x:Name="SideLogoHost" Width="44" Height="44" CornerRadius="13" Background="{StaticResource HeaderGradient}">
                    <TextBlock Text="FS" Foreground="White" FontWeight="Bold" FontSize="16" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="Fine Studio" FontWeight="SemiBold" FontSize="16"/>
                    <TextBlock Text="Booking Management" Style="{StaticResource MutedText}" FontSize="11"/>
                  </StackPanel>
                </StackPanel>
                <Button x:Name="BtnNavDash" Content="Dashboard" Style="{StaticResource GhostButton}"/>
                <Button x:Name="BtnNavNew" Content="New Booking" Style="{StaticResource GhostButton}"/>
                <Button x:Name="BtnNavBookings" Content="Bookings" Style="{StaticResource GhostButton}"/>
              </StackPanel>
              <StackPanel DockPanel.Dock="Bottom">
                <Border Background="{DynamicResource NavHoverBrush}" CornerRadius="12" Padding="14,12" Margin="0,0,0,12">
                  <StackPanel>
                    <TextBlock x:Name="TxtSideUser" FontWeight="SemiBold"/>
                    <TextBlock x:Name="TxtSideStudio" Style="{StaticResource MutedText}" FontSize="12"/>
                  </StackPanel>
                </Border>
                <Button x:Name="BtnTheme" Content="Dark mode" Style="{StaticResource GhostButton}"/>
                <Button x:Name="BtnLogout" Content="Logout" Style="{StaticResource GhostButton}"/>
              </StackPanel>
            </DockPanel>
          </Border>

          <!-- Content -->
          <Grid Grid.Column="1" Margin="32,26,32,24">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0">
              <StackPanel VerticalAlignment="Center">
                <TextBlock x:Name="TxtPageTitle" Style="{StaticResource H1}"/>
                <TextBlock x:Name="TxtPageSub" Style="{StaticResource MutedText}" Margin="0,4,0,0"/>
              </StackPanel>
              <StackPanel x:Name="StepBar" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Visibility="Collapsed">
                <Border x:Name="Step1" Style="{StaticResource StepPill}"><TextBlock x:Name="Step1Text" Text="1  Client and event" FontSize="12"/></Border>
                <Border x:Name="Step2" Style="{StaticResource StepPill}"><TextBlock x:Name="Step2Text" Text="2  Equipment" FontSize="12"/></Border>
                <Border x:Name="Step3" Style="{StaticResource StepPill}"><TextBlock x:Name="Step3Text" Text="3  Deliverables and payment" FontSize="12"/></Border>
              </StackPanel>
            </Grid>

            <Grid Grid.Row="1" Margin="0,24,0,0">

              <!-- Dashboard -->
              <Grid x:Name="PageDash" Visibility="Collapsed">
                <Grid.RenderTransform><TranslateTransform/></Grid.RenderTransform>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock x:Name="TxtDashWelcome" Style="{StaticResource H2}" Margin="0,0,0,20"/>
                <UniformGrid Grid.Row="1" Columns="3">
                  <Border Background="{DynamicResource CardBrush}" CornerRadius="16" Padding="24" Margin="0,0,16,0">
                    <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08"/></Border.Effect>
                    <StackPanel>
                      <TextBlock Text="Bookings" Style="{StaticResource FieldLabel}"/>
                      <TextBlock x:Name="StatBookings" Text="0" Style="{StaticResource StatValue}"/>
                    </StackPanel>
                  </Border>
                  <Border Background="{DynamicResource CardBrush}" CornerRadius="16" Padding="24" Margin="0,0,16,0">
                    <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08"/></Border.Effect>
                    <StackPanel>
                      <TextBlock Text="Total value" Style="{StaticResource FieldLabel}"/>
                      <TextBlock x:Name="StatTotal" Text="Rs. 0" Style="{StaticResource StatValue}"/>
                    </StackPanel>
                  </Border>
                  <Border Background="{DynamicResource CardBrush}" CornerRadius="16" Padding="24">
                    <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08"/></Border.Effect>
                    <StackPanel>
                      <TextBlock Text="Outstanding" Style="{StaticResource FieldLabel}"/>
                      <TextBlock x:Name="StatRemaining" Text="Rs. 0" Style="{StaticResource StatValue}" Foreground="{DynamicResource AccentBrush}"/>
                    </StackPanel>
                  </Border>
                </UniformGrid>
                <Grid Grid.Row="2" Margin="0,28,0,0" VerticalAlignment="Top">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <Button x:Name="BtnDashNew" Grid.Column="0" Content="+  New booking" Style="{StaticResource PrimaryButton}" Height="130" FontSize="20" Margin="0,0,12,0"/>
                  <Button x:Name="BtnDashView" Grid.Column="1" Content="View all bookings" Style="{StaticResource SecondaryButton}" Height="130" FontSize="20" Margin="12,0,0,0"/>
                </Grid>
              </Grid>

              <!-- Wizard step 1 -->
              <Grid x:Name="PageBook1" Visibility="Collapsed">
                <Grid.RenderTransform><TranslateTransform/></Grid.RenderTransform>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="*"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Border Grid.Row="0" Background="{DynamicResource CardBrush}" CornerRadius="16" Padding="24,20,24,8" Margin="0,0,0,16">
                  <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08"/></Border.Effect>
                  <Grid>
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                      <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0" Margin="0,0,16,12">
                      <TextBlock Text="Client name *" Style="{StaticResource FieldLabel}"/>
                      <TextBox x:Name="TxtClient"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Margin="0,0,16,12">
                      <TextBlock Text="Client phone *" Style="{StaticResource FieldLabel}"/>
                      <TextBox x:Name="TxtClientPhone"/>
                    </StackPanel>
                    <StackPanel Grid.Column="2" Margin="0,0,0,12">
                      <TextBlock Text="Second phone (optional)" Style="{StaticResource FieldLabel}"/>
                      <TextBox x:Name="TxtClientPhone2"/>
                    </StackPanel>
                  </Grid>
                </Border>

                <Border Grid.Row="1" Background="{DynamicResource CardBrush}" CornerRadius="16" Padding="24,20">
                  <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08"/></Border.Effect>
                  <Grid>
                    <Grid.RowDefinitions>
                      <RowDefinition Height="Auto"/>
                      <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <Grid Grid.Row="0">
                      <TextBlock Text="Event details" Style="{StaticResource H2}"/>
                      <Button x:Name="BtnAddDay" Content="+  Add event day" Style="{StaticResource SecondaryButton}" Width="170" Height="38" HorizontalAlignment="Right"/>
                    </Grid>
                    <ScrollViewer Grid.Row="1" Margin="0,16,0,0" VerticalScrollBarVisibility="Auto">
                      <StackPanel x:Name="DayStack"/>
                    </ScrollViewer>
                  </Grid>
                </Border>

                <Grid Grid.Row="2" Margin="0,16,0,0">
                  <Button x:Name="BtnCancel1" Content="Cancel" Style="{StaticResource SecondaryButton}" Width="130" HorizontalAlignment="Left"/>
                  <Button x:Name="BtnNext1" Content="Next: equipment  &#8594;" Style="{StaticResource PrimaryButton}" Width="220" HorizontalAlignment="Right"/>
                </Grid>
              </Grid>

              <!-- Wizard step 2 -->
              <Grid x:Name="PageBook2" Visibility="Collapsed">
                <Grid.RenderTransform><TranslateTransform/></Grid.RenderTransform>
                <Grid.RowDefinitions>
                  <RowDefinition Height="*"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
                  <WrapPanel x:Name="EquipWrap"/>
                </ScrollViewer>
                <Grid Grid.Row="1" Margin="0,16,0,0">
                  <Button x:Name="BtnCancel2" Content="Cancel" Style="{StaticResource SecondaryButton}" Width="130" HorizontalAlignment="Left"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="BtnBack2" Content="Back" Style="{StaticResource SecondaryButton}" Width="130" Margin="0,0,12,0"/>
                    <Button x:Name="BtnNext2" Content="Next: deliverables  &#8594;" Style="{StaticResource PrimaryButton}" Width="230"/>
                  </StackPanel>
                </Grid>
              </Grid>

              <!-- Wizard step 3 -->
              <Grid x:Name="PageBook3" Visibility="Collapsed">
                <Grid.RenderTransform><TranslateTransform/></Grid.RenderTransform>
                <Grid.RowDefinitions>
                  <RowDefinition Height="*"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
                  <StackPanel Margin="0,0,8,0">
                    <Border Background="{DynamicResource CardBrush}" CornerRadius="16" Padding="24,20" Margin="0,0,0,16">
                      <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08"/></Border.Effect>
                      <StackPanel>
                        <TextBlock Text="Deliverables" Style="{StaticResource H2}" Margin="0,0,0,14"/>
                        <Grid Margin="0,0,0,8">
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="300"/>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <TextBlock Text="Deliverable" Style="{StaticResource FieldLabel}"/>
                          <TextBlock Grid.Column="1" Text="Qty / days" Style="{StaticResource FieldLabel}"/>
                          <TextBlock Grid.Column="2" Text="Details" Style="{StaticResource FieldLabel}"/>
                        </Grid>
                        <Grid Margin="0,0,0,10">
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="300"/>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <TextBlock Text="Complete Edited Film - Softcopy" VerticalAlignment="Center"/>
                          <TextBox x:Name="TxtDelFilm" Grid.Column="1" Width="100" HorizontalAlignment="Left" TextAlignment="Center"/>
                          <TextBlock Grid.Column="2" Text="number of days" Style="{StaticResource MutedText}" VerticalAlignment="Center" Margin="16,0,0,0"/>
                        </Grid>
                        <Grid Margin="0,0,0,10">
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="300"/>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <TextBlock Text="Complete Photos - Softcopy" VerticalAlignment="Center"/>
                          <TextBox x:Name="TxtDelPhotos" Grid.Column="1" Width="100" HorizontalAlignment="Left" TextAlignment="Center"/>
                          <TextBlock Grid.Column="2" Text="number of days" Style="{StaticResource MutedText}" VerticalAlignment="Center" Margin="16,0,0,0"/>
                        </Grid>
                        <Grid Margin="0,0,0,10">
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="300"/>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <TextBlock Text="Raw Data - Softcopy" VerticalAlignment="Center"/>
                          <TextBox x:Name="TxtDelRaw" Grid.Column="1" Width="100" HorizontalAlignment="Left" TextAlignment="Center"/>
                          <TextBlock Grid.Column="2" Text="number of days" Style="{StaticResource MutedText}" VerticalAlignment="Center" Margin="16,0,0,0"/>
                        </Grid>
                        <Grid Margin="0,0,0,10">
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="300"/>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <TextBlock Text="Indian Album" VerticalAlignment="Center"/>
                          <TextBox x:Name="TxtDelAlbum" Grid.Column="1" Width="100" HorizontalAlignment="Left" TextAlignment="Center"/>
                        </Grid>
                        <Grid Margin="0,0,0,10">
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="300"/>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <TextBlock Text="Printed Photo" VerticalAlignment="Center"/>
                          <TextBox x:Name="TxtDelPrint" Grid.Column="1" Width="100" HorizontalAlignment="Left" TextAlignment="Center"/>
                        </Grid>
                        <Grid Margin="0,0,0,10">
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="300"/>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <TextBlock Text="USB" VerticalAlignment="Center"/>
                          <TextBox x:Name="TxtDelUsb" Grid.Column="1" Width="100" HorizontalAlignment="Left" TextAlignment="Center"/>
                          <StackPanel Grid.Column="2" Orientation="Horizontal" Margin="16,0,0,0">
                            <TextBlock Text="Size (GB)" Style="{StaticResource MutedText}" VerticalAlignment="Center" Margin="0,0,10,0"/>
                            <TextBox x:Name="TxtDelGb" Width="140"/>
                          </StackPanel>
                        </Grid>
                        <Grid>
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="300"/>
                            <ColumnDefinition Width="130"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <TextBlock Text="Custom" VerticalAlignment="Center"/>
                          <TextBox x:Name="TxtDelCustomQty" Grid.Column="1" Width="100" HorizontalAlignment="Left" TextAlignment="Center"/>
                          <TextBox x:Name="TxtDelCustomName" Grid.Column="2" Margin="16,0,0,0" ToolTip="Type the deliverable name"/>
                        </Grid>
                      </StackPanel>
                    </Border>

                    <Border Background="{DynamicResource CardBrush}" CornerRadius="16" Padding="24,20">
                      <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08"/></Border.Effect>
                      <StackPanel>
                        <TextBlock Text="Payment" Style="{StaticResource H2}" Margin="0,0,0,14"/>
                        <Grid>
                          <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                          </Grid.ColumnDefinitions>
                          <StackPanel Grid.Column="0" Margin="0,0,16,0">
                            <TextBlock Text="Total amount (Rs.) *" Style="{StaticResource FieldLabel}"/>
                            <TextBox x:Name="TxtTotal"/>
                          </StackPanel>
                          <StackPanel Grid.Column="1" Margin="0,0,16,0">
                            <TextBlock Text="Advance paid (Rs.)" Style="{StaticResource FieldLabel}"/>
                            <TextBox x:Name="TxtAdvance"/>
                          </StackPanel>
                          <StackPanel Grid.Column="2">
                            <TextBlock Text="Remaining (Rs.)" Style="{StaticResource FieldLabel}"/>
                            <TextBlock x:Name="TxtRemaining" Text="-" FontSize="22" FontWeight="SemiBold" Foreground="{DynamicResource AccentBrush}" Margin="0,4,0,0"/>
                          </StackPanel>
                        </Grid>
                        <StackPanel Margin="0,14,0,0">
                          <TextBlock Text="Payment note" Style="{StaticResource FieldLabel}"/>
                          <TextBox x:Name="TxtPayNote"/>
                        </StackPanel>
                      </StackPanel>
                    </Border>
                  </StackPanel>
                </ScrollViewer>
                <Grid Grid.Row="1" Margin="0,16,0,0">
                  <Button x:Name="BtnCancel3" Content="Cancel" Style="{StaticResource SecondaryButton}" Width="130" HorizontalAlignment="Left"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button x:Name="BtnBack3" Content="Back" Style="{StaticResource SecondaryButton}" Width="130" Margin="0,0,12,0"/>
                    <Button x:Name="BtnFinish" Content="Finish and save" Style="{StaticResource PrimaryButton}" Width="230"/>
                  </StackPanel>
                </Grid>
              </Grid>

              <!-- Bookings -->
              <Grid x:Name="PageBookings" Visibility="Collapsed">
                <Grid.RenderTransform><TranslateTransform/></Grid.RenderTransform>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="*"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBox x:Name="TxtSearch" Width="380" HorizontalAlignment="Left" Margin="0,0,0,16" ToolTip="Search by booking ID or client name"/>
                <Border Grid.Row="1" Background="{DynamicResource CardBrush}" CornerRadius="16" ClipToBounds="True">
                  <Border.Effect><DropShadowEffect BlurRadius="12" ShadowDepth="1" Opacity="0.08"/></Border.Effect>
                  <DataGrid x:Name="GridBookings" Style="{StaticResource BookingsGrid}"/>
                </Border>
                <TextBlock x:Name="TxtSummary" Grid.Row="2" Margin="0,14,0,14" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource AccentBrush}"/>
                <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
                  <Button x:Name="BtnCopy" Content="Copy confirmation" Style="{StaticResource SecondaryButton}" Width="190"/>
                  <Button x:Name="BtnEdit" Content="Edit booking" Style="{StaticResource PrimaryButton}" Width="160" Margin="12,0,0,0"/>
                  <Button x:Name="BtnDelete" Content="Delete booking" Style="{StaticResource DangerButton}" Width="160" Margin="12,0,0,0"/>
                </StackPanel>
              </Grid>

            </Grid>
          </Grid>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$script:DialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Fine Studio Booking" WindowStyle="SingleBorderWindow"
        Background="{DynamicResource BgBrush}" SizeToContent="Height" Width="500"
        MinHeight="220" MaxWidth="560" ResizeMode="NoResize" ShowInTaskbar="False"
        WindowStartupLocation="CenterOwner" Topmost="True" UseLayoutRounding="True"
        SnapsToDevicePixels="True">
  <Border Margin="0" Background="{DynamicResource CardBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Padding="0">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Border Grid.Row="0" Background="{DynamicResource AccentBrush}" Padding="22,18">
        <StackPanel Orientation="Horizontal">
          <Border Width="34" Height="34" CornerRadius="17" Background="#33FFFFFF" VerticalAlignment="Center" Margin="0,0,12,0">
            <TextBlock Text="!" FontSize="21" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock x:Name="DlgTitle" FontSize="19" FontWeight="SemiBold" Foreground="{DynamicResource OnAccentBrush}" VerticalAlignment="Center" TextWrapping="Wrap"/>
        </StackPanel>
      </Border>
      <TextBlock x:Name="DlgMsg" Grid.Row="1" Margin="24,22,24,24" TextWrapping="Wrap" FontSize="15" LineHeight="22" Foreground="{DynamicResource TextBrush}"/>
      <Border Grid.Row="2" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="20,14">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="DlgCancel" Content="Cancel" Style="{StaticResource SecondaryButton}" Width="112" Margin="0,0,10,0" Visibility="Collapsed"/>
          <Button x:Name="DlgOk" Content="OK, got it" Style="{StaticResource PrimaryButton}" Width="132"/>
        </StackPanel>
      </Border>
    </Grid>
  </Border>
</Window>
'@
# ============================================================
# Data helpers (same JSON format as the WinForms edition)
# ============================================================
function Ensure-DataDir {
    if (-not (Test-Path -LiteralPath $script:DataDir)) {
        New-Item -ItemType Directory -Path $script:DataDir | Out-Null
    }
}

function Read-JsonList([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Read-JsonList received an empty file path.' }
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $data = $raw | ConvertFrom-Json
    return @($data)
}

function Write-JsonList([string]$Path, $Items) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Write-JsonList received an empty file path.' }
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if ([string]::IsNullOrWhiteSpace($parent)) { throw 'Could not determine the data file parent folder.' }
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $list = @($Items)
    if ($list.Count -eq 0) { $json = '[]' }
    else { $json = ConvertTo-Json -InputObject $list -Depth 10 }
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Get-PasswordHash([string]$Password, [string]$Salt) {
    $saltBytes = [Convert]::FromBase64String($Salt)
    $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $saltBytes, 100000)
    return [Convert]::ToBase64String($kdf.GetBytes(32))
}

function New-PasswordRecord([string]$Password) {
    $saltBytes = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($saltBytes)
    $salt = [Convert]::ToBase64String($saltBytes)
    return [pscustomobject]@{ Salt = $salt; Hash = (Get-PasswordHash $Password $salt) }
}

function Test-Phone([string]$Phone) {
    return ($Phone -match '^\+?[0-9][0-9 \-]{5,18}$')
}

function ConvertTo-Amount([string]$Text) {
    $clean = ($Text -replace ',', '').Trim()
    if ($clean -eq '') { return $null }
    $value = 0.0
    if ([double]::TryParse($clean, [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$value)) {
        return $value
    }
    return $null
}

function Get-IntText([string]$Text) {
    $value = 0
    if ([int]::TryParse($Text.Trim(), [ref]$value)) { return $value }
    return 0
}

function Format-Money($Value) {
    $v = [double]$Value
    if ([math]::Floor($v) -eq $v) { return $v.ToString('N0', $script:Inv) }
    return $v.ToString('N2', $script:Inv)
}

function Format-DayDate([string]$IsoDate) {
    return ([datetime]::ParseExact($IsoDate, 'yyyy-MM-dd', $script:Inv)).ToString('dd MMM yyyy', $script:Inv)
}

function Contains-Text([string]$Haystack, [string]$Needle) {
    if ([string]::IsNullOrEmpty($Needle)) { return $true }
    return ($Haystack.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Set-ClipboardText([string]$Text) {
    for ($try = 0; $try -lt 6; $try++) {
        try { [System.Windows.Clipboard]::SetText($Text); return } catch { Start-Sleep -Milliseconds 60 }
    }
    try { Set-Clipboard -Value $Text } catch {}
}

function Tag-If([bool]$Condition) {
    if ($Condition) { return 'active' }
    return $null
}

# ============================================================
# Booking ID and confirmation text
# ============================================================
function New-BookingId([string]$Studio, [datetime]$When, $Existing) {
    $words  = @(($Studio -replace '[^A-Za-z\s]', '') -split '\s+' | Where-Object { $_ -ne '' })
    $prefix = (($words | ForEach-Object { $_.Substring(0, 1) }) -join '').ToUpper()
    if ($prefix -eq '') { $prefix = 'BK' }

    $ids   = @($Existing | ForEach-Object { $_.BookingId })
    $stamp = $When
    $id    = '{0}-{1}' -f $prefix, $stamp.ToString('yyMMHHmm', $script:Inv)
    while ($ids -contains $id) {
        $stamp = $stamp.AddMinutes(1)
        $id    = '{0}-{1}' -f $prefix, $stamp.ToString('yyMMHHmm', $script:Inv)
    }
    return $id
}

function New-ConfirmationText($b) {
    $d = $script:Dash
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("*$($b.StudioName.ToUpper())*")
    $lines.Add('Booking Confirmation')
    $lines.Add('')
    $lines.Add("*Booking ID:* $($b.BookingId)")
    $lines.Add("*Client Name:* $($b.ClientName)")
    $lines.Add("Contact: $($b.ClientPhone)")
    if ($b.ClientPhone2) { $lines.Add("Contact 2: $($b.ClientPhone2)") }
    $lines.Add('')
    $lines.Add('*EVENT DETAILS*')
    $lines.Add($script:Rule)

    $i = 0
    foreach ($day in @($b.Days)) {
        $i++
        $lines.Add("Day $i $d $($day.Name)")
        $lines.Add("$(Format-DayDate $day.Date) | $($day.Time)")
        $lines.Add([string]$day.Venue)
        $eqText = (@($day.Equipment) | ForEach-Object { '{0}x {1}' -f $_.Qty, $_.Item }) -join ' | '
        $lines.Add($eqText)
        $lines.Add('')
    }

    $delText = (@($b.Deliverables) | ForEach-Object { '{0} x {1}{2}' -f $_.Label, $_.Qty, $_.Unit }) -join ' | '
    $lines.Add("Deliverable: $delText")
    $lines.Add('')
    $lines.Add('PAYMENT DETAILS')
    $lines.Add("- Total: Rs. $(Format-Money $b.Total)")
    $lines.Add("- Advance: Rs. $(Format-Money $b.Advance)")
    $lines.Add("- Remaining: Rs. $(Format-Money $b.Remaining)")
    if ($b.PaymentNote) { $lines.Add("Note: $($b.PaymentNote)") }
    $lines.Add($script:Rule)
    $lines.Add("Booked By: $($b.BookedByName) ($($b.BookedByContact))")
    $lines.Add("Thank you for choosing $($b.StudioName)!")

    return ($lines -join "`r`n")
}

# ============================================================
# Animation helpers (all motion is done with real WPF animations)
# ============================================================
function New-Ease {
    $e = New-Object System.Windows.Media.Animation.CubicEase
    $e.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    return $e
}

function Start-Anim {
    param($Target, $Prop, [double]$From, [double]$To, [int]$Ms, [int]$Delay = 0)
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.From = $From
    $a.To = $To
    $a.Duration = New-Object System.Windows.Duration -ArgumentList ([TimeSpan]::FromMilliseconds($Ms))
    $a.EasingFunction = New-Ease
    if ($Delay -gt 0) { $a.BeginTime = [TimeSpan]::FromMilliseconds($Delay) }
    $Target.BeginAnimation($Prop, $a)
}

function Start-ColorAnim($Brush, [string]$Hex, [int]$Ms) {
    # Resource brushes can be frozen by WPF. Set a fresh brush instead of
    # animating a Freezable resource, which avoids sealed/frozen brush errors.
    if ($null -eq $Brush) { return }
    $color = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    if (-not $Brush.IsFrozen -and $Brush.IsSealed -eq $false) {
        $Brush.Color = $color
    }
}

function Shake-LoginCard {
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.From = -10
    $a.To = 10
    $a.Duration = New-Object System.Windows.Duration -ArgumentList ([TimeSpan]::FromMilliseconds(60))
    $a.AutoReverse = $true
    $a.RepeatBehavior = New-Object System.Windows.Media.Animation.RepeatBehavior -ArgumentList 3.0
    $script:LoginCard.RenderTransform.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $a)
}

function Play-Intro {
    Start-Anim $script:Shell ([System.Windows.UIElement]::OpacityProperty) 0 1 520
    Start-Anim $script:LoginCard.RenderTransform ([System.Windows.Media.TranslateTransform]::YProperty) 26 0 620 120
    Start-Anim $script:LoginCard ([System.Windows.UIElement]::OpacityProperty) 0 1 620 120
}

# ============================================================
# Theme (every colour animates from the old palette to the new one)
# ============================================================
function Set-Theme([bool]$Dark, [bool]$Animate = $true) {
    $script:IsDark = $Dark
    $palette = $script:LightPalette
    if ($Dark) { $palette = $script:DarkPalette }

    # Always replace each resource with a brand-new brush. WPF can freeze
    # brushes loaded from XAML, so never animate or mutate resource brushes.
    # Theme switching is deliberately immediate to avoid UI stutter on slower PCs.
    foreach ($key in $palette.Keys) {
        $hex = [string]$palette[$key]
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $script:Res[$key] = [System.Windows.Media.SolidColorBrush]::new($color)
    }

    # Override system brush keys too, for native ComboBox and DatePicker popups.
    foreach ($sysName in $script:SysMap.Keys) {
        $property = [System.Windows.SystemColors].GetProperty($sysName)
        if ($null -eq $property) { continue }
        $sysKey = $property.GetValue($null, $null)
        $paletteKey = $script:SysMap[$sysName]
        if (-not $palette.Contains($paletteKey)) { continue }
        $hex = [string]$palette[$paletteKey]
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $script:Res[$sysKey] = [System.Windows.Media.SolidColorBrush]::new($color)
    }

    if ($Dark) { $script:BtnTheme.Content = 'Light mode' } else { $script:BtnTheme.Content = 'Dark mode' }
}

# ============================================================
# Dialogs (styled XAML windows instead of MessageBox)
# ============================================================
function Show-Dlg([string]$Title, [string]$Message, [bool]$Confirm = $false) {
    $script:DlgWin = [System.Windows.Markup.XamlReader]::Parse($script:DialogXaml)
    $script:DlgWin.Owner = $script:Win
    $script:DlgWin.WindowStartupLocation = 'CenterOwner'
    $script:DlgWin.FindName('DlgTitle').Text = $Title
    $script:DlgWin.FindName('DlgMsg').Text = $Message
    $ok = $script:DlgWin.FindName('DlgOk')
    $cancel = $script:DlgWin.FindName('DlgCancel')
    if ($Confirm) {
        $cancel.Visibility = 'Visible'
        $ok.Content = 'Yes, continue'
    }
    $ok.Add_Click({ $script:DlgWin.DialogResult = $true })
    $cancel.Add_Click({ $script:DlgWin.DialogResult = $false })
    return [bool]$script:DlgWin.ShowDialog()
}

function Show-Warn([string]$Message) {
    [void](Show-Dlg 'Please check' $Message $false)
}

# ============================================================
# Page navigation
# ============================================================
function Update-PageHeader([string]$Key) {
    $title = ''
    $sub = ''
    switch ($Key) {
        'dash'     { $title = 'Dashboard';                 $sub = 'Overview of your studio bookings' }
        'book1'    { $title = 'New Booking';               $sub = 'Client details and event days' }
        'book2'    { $title = 'Equipment';                 $sub = 'Equipment needed for each event day' }
        'book3'    { $title = 'Deliverables and Payment';  $sub = 'Choose deliverables and record the payment' }
        'bookings' { $title = 'Bookings';                  $sub = 'Search, view, edit and delete bookings' }
    }
    if ($Key -eq 'book1' -and -not [string]::IsNullOrEmpty($script:EditingId)) { $title = 'Edit Booking' }
    $script:TxtPageTitle.Text = $title
    $script:TxtPageSub.Text = $sub
    # Keep header updates immediate; avoid per-navigation animation overhead.
    $script:TxtPageTitle.Opacity = 1

    $step = 0
    if ($Key -eq 'book1') { $step = 1 }
    if ($Key -eq 'book2') { $step = 2 }
    if ($Key -eq 'book3') { $step = 3 }
    if ($step -gt 0) { $script:StepBar.Visibility = 'Visible' } else { $script:StepBar.Visibility = 'Collapsed' }
    $script:Step1.Tag = Tag-If ($step -eq 1)
    $script:Step2.Tag = Tag-If ($step -eq 2)
    $script:Step3.Tag = Tag-If ($step -eq 3)
}

function Set-Nav([string]$Key) {
    $script:BtnNavDash.Tag     = Tag-If ($Key -eq 'dash')
    $script:BtnNavNew.Tag      = Tag-If ($Key -like 'book*')
    $script:BtnNavBookings.Tag = Tag-If ($Key -eq 'bookings')
}

function Hide-AllPages {
    foreach ($k in @($script:PageMap.Keys)) { $script:PageMap[$k].Visibility = 'Collapsed' }
    $script:CurrentPage = ''
}

function Show-Page([string]$Key) {
    $new = $script:PageMap[$Key]
    if ($null -eq $new) { return }
    if ($script:CurrentPage -eq $Key) {
        Update-PageHeader $Key
        return
    }
    if ($script:CurrentPage -ne '') { $script:PageMap[$script:CurrentPage].Visibility = 'Collapsed' }
    $script:CurrentPage = $Key
    # Instant page switch: avoid opacity/slide animations that can stutter
    # while WPF recalculates layouts on slower PCs.
    $new.Opacity = 1
    if ($new.RenderTransform -is [System.Windows.Media.TranslateTransform]) {
        $new.RenderTransform.X = 0
    }
    $new.Visibility = 'Visible'
    Update-PageHeader $Key
}

function Go-Nav([string]$Key) {
    if ($script:CurrentPage -like 'book*' -and $Key -notlike 'book*') {
        if (-not (Show-Dlg 'Leave booking' 'Unsaved changes will be discarded. Continue?' $true)) { return }
        Reset-Wizard
    }
    if ($Key -eq 'dash') { Refresh-Dashboard }
    if ($Key -eq 'bookings') { Refresh-Grid }
    if ($Key -eq 'book1' -and $script:CurrentPage -notlike 'book*') { Reset-Wizard }
    Set-Nav $Key
    Show-Page $Key
}

# ============================================================
# Login and sign up
# ============================================================
function Refresh-Users([string]$SelectName = '') {
    $users = @(Read-JsonList $script:UsersFile | Sort-Object FullName)
    $script:CboUser.ItemsSource = $users
    $script:CboUser.SelectedIndex = -1
    if ($users.Count -eq 0) { return }
    $index = 0
    for ($i = 0; $i -lt $users.Count; $i++) {
        if ($SelectName -ne '' -and $users[$i].FullName -ieq $SelectName) { $index = $i }
    }
    $script:CboUser.SelectedIndex = $index
}

function Show-AuthTab([bool]$Signup) {
    $script:BtnTabLogin.Tag  = Tag-If (-not $Signup)
    $script:BtnTabSignup.Tag = Tag-If $Signup
    if ($Signup) {
        $script:PanelLogin.Visibility = 'Collapsed'
        $script:PanelSignup.Visibility = 'Visible'
        Start-Anim $script:PanelSignup ([System.Windows.UIElement]::OpacityProperty) 0 1 300
    }
    else {
        $script:PanelSignup.Visibility = 'Collapsed'
        $script:PanelLogin.Visibility = 'Visible'
        Start-Anim $script:PanelLogin ([System.Windows.UIElement]::OpacityProperty) 0 1 300
    }
}

function Do-Login {
    $user = $script:CboUser.SelectedItem
    if ($null -eq $user) { Show-Warn 'Please select a registered user.'; return }
    $password = $script:PwdLogin.Password
    if ((Get-PasswordHash $password $user.Salt) -cne $user.Hash) {
        $script:PwdLogin.Clear()
        Shake-LoginCard
        Show-Warn 'The password is incorrect. Please try again.'
        [void]$script:PwdLogin.Focus()
        return
    }
    $script:CurrentUser = $user
    # Persist only the account ID, never the password. This keeps the same profile
    # active across app restarts until the user explicitly logs out.
    try {
        Set-Content -LiteralPath $script:SessionFile -Value ([string]$user.Id) -Encoding UTF8
    } catch {
        Show-Warn "Could not save the login session. The app will open, but you may need to sign in again next time."
    }
    $script:PwdLogin.Clear()
    Enter-App
}

function Do-Signup {
    $studio  = $script:TxtSuStudio.Text.Trim()
    $full    = $script:TxtSuFull.Text.Trim()
    $contact = $script:TxtSuContact.Text.Trim()
    $password = $script:PwdSignup.Password

    if ($studio -eq '')  { Show-Warn 'Studio name is required.'; [void]$script:TxtSuStudio.Focus(); return }
    if ($full -eq '')    { Show-Warn 'Full name is required.'; [void]$script:TxtSuFull.Focus(); return }
    if ($contact -eq '') { Show-Warn 'Contact number is required.'; [void]$script:TxtSuContact.Focus(); return }
    if (-not (Test-Phone $contact)) { Show-Warn 'Contact number is not valid. Use 6 to 19 digits, optionally starting with +.'; [void]$script:TxtSuContact.Focus(); return }
    if ($password.Length -lt 4) { Show-Warn 'Password must be at least 4 characters.'; [void]$script:PwdSignup.Focus(); return }

    $users = @(Read-JsonList $script:UsersFile)
    if (@($users | Where-Object { $_.FullName -ieq $full }).Count -gt 0) {
        Show-Warn "A user named '$full' already exists. Please use a different full name."
        [void]$script:TxtSuFull.Focus()
        return
    }

    $record = New-PasswordRecord $password
    $user = [pscustomobject]@{
        Id            = [guid]::NewGuid().ToString()
        StudioName    = $studio
        FullName      = $full
        ContactNumber = $contact
        Salt          = $record.Salt
        Hash          = $record.Hash
        CreatedAt     = (Get-Date).ToString('s', $script:Inv)
    }
    Write-JsonList $script:UsersFile (@($users) + $user)

    $script:TxtSuStudio.Clear()
    $script:TxtSuFull.Clear()
    $script:TxtSuContact.Clear()
    $script:PwdSignup.Clear()

    Refresh-Users $full
    Show-AuthTab $false
    Show-Dlg 'Account created' "Welcome, $full. Please sign in with your password." $false | Out-Null
}

function Delete-UserAccount {
    $user = $script:CboUser.SelectedItem
    if ($null -eq $user) { Show-Warn 'Please select the user account you want to delete.'; return }

    $password = $script:PwdLogin.Password
    if ([string]::IsNullOrEmpty($password)) {
        Show-Warn "Enter the selected user password to confirm account deletion."
        [void]$script:PwdLogin.Focus()
        return
    }
    if ((Get-PasswordHash $password $user.Salt) -cne $user.Hash) {
        $script:PwdLogin.Clear()
        Show-Warn 'The password is incorrect. The account was not deleted.'
        [void]$script:PwdLogin.Focus()
        return
    }

    $userBookings = @(Read-JsonList $script:BookingsFile | Where-Object { [string]$_.StudioUserId -eq [string]$user.Id })
    $message = "Permanently delete account '$($user.FullName)'?`r`n`r`nThis will also permanently delete $($userBookings.Count) booking(s) belonging to this account. This cannot be undone."
    if (-not (Show-Dlg 'Delete user account' $message $true)) {
        $script:PwdLogin.Clear()
        return
    }

    try {
        $users = @(Read-JsonList $script:UsersFile | Where-Object { [string]$_.Id -ne [string]$user.Id })
        Write-JsonList $script:UsersFile $users

        if ($userBookings.Count -gt 0) {
            $allBookings = @(Read-JsonList $script:BookingsFile | Where-Object { [string]$_.StudioUserId -ne [string]$user.Id })
            Write-JsonList $script:BookingsFile $allBookings
        }

        # If a stale saved session references this account, remove it as well.
        try {
            if (Test-Path -LiteralPath $script:SessionFile) {
                $savedId = (Get-Content -LiteralPath $script:SessionFile -Raw -ErrorAction Stop).Trim()
                if ($savedId -eq [string]$user.Id) {
                    Remove-Item -LiteralPath $script:SessionFile -Force -ErrorAction SilentlyContinue
                }
            }
        } catch { }

        $script:PwdLogin.Clear()
        Refresh-Users
        Show-Dlg 'Account deleted' "The account '$($user.FullName)' and its associated bookings have been deleted." $false | Out-Null
    } catch {
        Show-Warn "Could not completely delete the account. Please check that the data files are writable. Details: $($_.Exception.Message)"
    }
}

function Enter-App {
    $script:TxtSideUser.Text = $script:CurrentUser.FullName
    $script:TxtSideStudio.Text = $script:CurrentUser.StudioName
    $script:LoginView.Visibility = 'Collapsed'
    $script:AppView.Visibility = 'Visible'
    Start-Anim $script:AppView ([System.Windows.UIElement]::OpacityProperty) 0 1 380
    Start-Anim $script:AppView.RenderTransform ([System.Windows.Media.TranslateTransform]::XProperty) 30 0 440
    Hide-AllPages
    Refresh-Dashboard
    Set-Nav 'dash'
    Show-Page 'dash'
}

function Do-Logout {
    # Explicit logout removes the saved session.
    try {
        if (-not [string]::IsNullOrWhiteSpace($script:SessionFile) -and (Test-Path -LiteralPath $script:SessionFile)) {
            Remove-Item -LiteralPath $script:SessionFile -Force -ErrorAction SilentlyContinue
        }
    } catch { }
    $script:CurrentUser = $null
    $script:EditingId = $null
    Hide-AllPages
    $script:AppView.Visibility = 'Collapsed'
    $script:LoginView.Visibility = 'Visible'
    Start-Anim $script:LoginView ([System.Windows.UIElement]::OpacityProperty) 0 1 380
    Refresh-Users
    Show-AuthTab $false
}

# ============================================================
# Dashboard
# ============================================================
function Refresh-Dashboard {
    $u = $script:CurrentUser
    if ($null -eq $u) { return }
    $script:TxtDashWelcome.Text = "Welcome, $($u.FullName)   |   " + (Get-Date).ToString('dddd, dd MMMM yyyy', $script:Inv)
    $mine = @(Read-JsonList $script:BookingsFile | Where-Object { $_.StudioUserId -eq $u.Id })
    $total = 0.0
    $rem = 0.0
    foreach ($b in $mine) {
        $total += [double]$b.Total
        $rem   += [double]$b.Remaining
    }
    $script:StatBookings.Text  = [string]$mine.Count
    $script:StatTotal.Text     = 'Rs. ' + (Format-Money $total)
    $script:StatRemaining.Text = 'Rs. ' + (Format-Money $rem)
}

# ============================================================
# Booking wizard
# ============================================================
function Put([System.Windows.Controls.Grid]$Grid, $El, [int]$R, [int]$C, [int]$CS = 1) {
    [System.Windows.Controls.Grid]::SetRow($El, $R)
    [System.Windows.Controls.Grid]::SetColumn($El, $C)
    if ($CS -gt 1) { [System.Windows.Controls.Grid]::SetColumnSpan($El, $CS) }
    [void]$Grid.Children.Add($El)
}

function New-RowDef {
    $rd = New-Object System.Windows.Controls.RowDefinition
    $rd.Height = [System.Windows.GridLength]::Auto
    return $rd
}

function New-Text([string]$Text, [string]$StyleKey = '') {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.VerticalAlignment = 'Center'
    if ($StyleKey -ne '') { $tb.Style = $script:Res[$StyleKey] }
    return $tb
}

function New-Label([string]$Text) {
    $tb = New-Text $Text 'FieldLabel'
    $tb.Margin = [System.Windows.Thickness]::new(0, 0, 14, 6)
    return $tb
}

function Update-RowState($row) {
    $row.TxtCustomEvent.IsEnabled = ([string]$row.CboEvent.SelectedItem -eq $script:CustomLabel)
    $row.TxtCustomTime.IsEnabled  = ([string]$row.CboTime.SelectedItem -eq $script:CustomLabel)
}

function Get-EventName($row) {
    if ($null -eq $row -or $null -eq $row.CboEvent) { return '' }
    $sel = [string]$row.CboEvent.SelectedItem
    if ($sel -eq $script:CustomLabel) {
        if ($null -eq $row.TxtCustomEvent) { return '' }
        return ([string]$row.TxtCustomEvent.Text).Trim()
    }
    return $sel
}

function Get-TimeText($row) {
    if ($null -eq $row -or $null -eq $row.CboTime) { return '' }
    $sel = [string]$row.CboTime.SelectedItem
    if ($sel -eq $script:CustomLabel) {
        if ($null -eq $row.TxtCustomTime) { return '' }
        return ([string]$row.TxtCustomTime.Text).Trim()
    }
    return $sel
}

function New-DayRow {
    $row = @{ EquipValues = @{}; CustomName = ''; CustomQty = ''; Title = $null }

    $border = New-Object System.Windows.Controls.Border
    $border.Background = $script:Res['RowBrush']
    $border.CornerRadius = [System.Windows.CornerRadius]::new(14)
    $border.Padding = [System.Windows.Thickness]::new(18, 14, 18, 16)
    $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
    $border.RenderTransform = New-Object System.Windows.Media.TranslateTransform
    $row.Border = $border
    $border.Tag = $row

    $g = New-Object System.Windows.Controls.Grid
    for ($c = 0; $c -lt 3; $c++) { [void]$g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition)) }
    $autoCol = New-Object System.Windows.Controls.ColumnDefinition
    $autoCol.Width = [System.Windows.GridLength]::Auto
    [void]$g.ColumnDefinitions.Add($autoCol)
    for ($r = 0; $r -lt 5; $r++) { [void]$g.RowDefinitions.Add((New-RowDef)) }
    $border.Child = $g

    $row.Title = New-Text 'Event day' 'H2'
    $row.Title.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    Put $g $row.Title 0 0 4

    Put $g (New-Label 'Event name') 1 0
    Put $g (New-Label 'Custom event name') 1 1
    Put $g (New-Label 'Event date') 1 2

    $cboEvent = New-Object System.Windows.Controls.ComboBox
    $cboEvent.ItemsSource = $script:EventOptions
    $cboEvent.Margin = [System.Windows.Thickness]::new(0, 0, 14, 14)
    $cboEvent.Tag = $row
    $cboEvent.SelectedIndex = 0
    $row.CboEvent = $cboEvent
    Put $g $cboEvent 2 0

    $txtCustomEvent = New-Object System.Windows.Controls.TextBox
    $txtCustomEvent.Margin = [System.Windows.Thickness]::new(0, 0, 14, 14)
    $txtCustomEvent.IsEnabled = $false
    $row.TxtCustomEvent = $txtCustomEvent
    Put $g $txtCustomEvent 2 1

    $dp = New-Object System.Windows.Controls.DatePicker
    $dp.SelectedDate = (Get-Date).Date
    $dp.Margin = [System.Windows.Thickness]::new(0, 0, 14, 14)
    $row.DtDate = $dp
    Put $g $dp 2 2

    $btnRemove = New-Object System.Windows.Controls.Button
    $btnRemove.Content = 'Remove'
    $btnRemove.Style = $script:Res['SecondaryButton']
    $btnRemove.Width = 110
    $btnRemove.Height = 40
    $btnRemove.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
    $btnRemove.Tag = $row
    $btnRemove.Add_Click({ param($s, $e) Remove-DayRow $s.Tag })
    Put $g $btnRemove 2 3

    Put $g (New-Label 'Time') 3 0
    Put $g (New-Label 'Custom time') 3 1
    Put $g (New-Label 'Venue') 3 2

    $cboTime = New-Object System.Windows.Controls.ComboBox
    $cboTime.ItemsSource = $script:TimeOptions
    $cboTime.Margin = [System.Windows.Thickness]::new(0, 0, 14, 0)
    $cboTime.Tag = $row
    $cboTime.SelectedIndex = 0
    $row.CboTime = $cboTime
    Put $g $cboTime 4 0

    $txtCustomTime = New-Object System.Windows.Controls.TextBox
    $txtCustomTime.Margin = [System.Windows.Thickness]::new(0, 0, 14, 0)
    $txtCustomTime.IsEnabled = $false
    $row.TxtCustomTime = $txtCustomTime
    Put $g $txtCustomTime 4 1

    $txtVenue = New-Object System.Windows.Controls.TextBox
    $txtVenue.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
    $row.TxtVenue = $txtVenue
    Put $g $txtVenue 4 2

    $cboEvent.Add_SelectionChanged({ param($s, $e) Update-RowState $s.Tag })
    $cboTime.Add_SelectionChanged({ param($s, $e) Update-RowState $s.Tag })
    Update-RowState $row

    return $row
}

function Refresh-DayTitles {
    $i = 0
    foreach ($row in $script:DayRows) {
        $i++
        $row.Title.Text = "Event day $i"
    }
}

function Fill-DayRow($row, $data) {
    if ((@($script:EventOptions) -contains [string]$data.Name) -and ([string]$data.Name -ne $script:CustomLabel)) {
        $row.CboEvent.SelectedItem = [string]$data.Name
    }
    else {
        $row.CboEvent.SelectedItem = $script:CustomLabel
        $row.TxtCustomEvent.Text = [string]$data.Name
    }
    if ((@($script:TimeOptions) -contains [string]$data.Time) -and ([string]$data.Time -ne $script:CustomLabel)) {
        $row.CboTime.SelectedItem = [string]$data.Time
    }
    else {
        $row.CboTime.SelectedItem = $script:CustomLabel
        $row.TxtCustomTime.Text = [string]$data.Time
    }
    Update-RowState $row
    $row.DtDate.SelectedDate = [datetime]::ParseExact([string]$data.Date, 'yyyy-MM-dd', $script:Inv)
    $row.TxtVenue.Text = [string]$data.Venue

    foreach ($eq in @($data.Equipment)) {
        $idx = [array]::IndexOf($script:EquipmentList, [string]$eq.Item)
        if ($idx -ge 0 -and $idx -lt 7) { $row.EquipValues[$idx] = [string]$eq.Qty }
        else {
            $row.CustomName = [string]$eq.Item
            $row.CustomQty = [string]$eq.Qty
        }
    }
}

function Add-DayRow($data = $null) {
    $row = New-DayRow
    if ($null -ne $data) { Fill-DayRow $row $data }
    [void]$script:DayRows.Add($row)
    [void]$script:DayStack.Children.Add($row.Border)
    Refresh-DayTitles
    # Add booking rows without entrance animations to keep scrolling/navigation responsive.
    $row.Border.Opacity = 1
    if ($row.Border.RenderTransform -is [System.Windows.Media.TranslateTransform]) { $row.Border.RenderTransform.Y = 0 }
}

function Remove-DayRow($row) {
    if ($script:DayRows.Count -le 1) { Show-Warn 'At least one event day is required.'; return }
    [void]$script:DayRows.Remove($row)
    [void]$script:DayStack.Children.Remove($row.Border)
    Refresh-DayTitles
}

function Save-EquipState {
    foreach ($e in $script:EquipBoxes) {
        $v = $e.Box.Text.Trim()
        if ($e.Key -is [int]) { $e.Row.EquipValues[$e.Key] = $v }
        elseif ($e.Key -eq 'CustomName') { $e.Row.CustomName = $v }
        else { $e.Row.CustomQty = $v }
    }
}

function New-QtyBox([string]$Text) {
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Text = $Text
    $tb.Width = 110
    $tb.HorizontalAlignment = 'Left'
    $tb.TextAlignment = 'Center'
    $tb.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
    return $tb
}

function Build-EquipPage {
    $script:EquipWrap.Children.Clear()
    $script:EquipBoxes = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($row in $script:DayRows) {
        $i++
        $card = New-Object System.Windows.Controls.Border
        $card.Background = $script:Res['CardBrush']
        $card.CornerRadius = [System.Windows.CornerRadius]::new(16)
        $card.Padding = [System.Windows.Thickness]::new(22, 20, 22, 18)
        $card.Margin = [System.Windows.Thickness]::new(0, 0, 18, 18)
        $card.Width = 500
        $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $shadow.BlurRadius = 18
        $shadow.ShadowDepth = 1
        $shadow.Opacity = 0.12
        $card.Effect = $shadow

        $sp = New-Object System.Windows.Controls.StackPanel
        $dateText = ''
        if ($null -ne $row -and $null -ne $row.DtDate) {
            $selectedDate = $row.DtDate.SelectedDate
            if ($null -ne $selectedDate) { $dateText = ([datetime]$selectedDate).ToString('dd MMM yyyy', $script:Inv) }
        }
        $eventName = Get-EventName $row
        [void]$sp.Children.Add((New-Text "Day $i   $eventName" 'H2'))
        $subText = New-Text ("$dateText   |   " + (Get-TimeText $row)) 'MutedText'
        $subText.Margin = [System.Windows.Thickness]::new(0, 2, 0, 14)
        [void]$sp.Children.Add($subText)

        $g = New-Object System.Windows.Controls.Grid
        [void]$g.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $qtyCol = New-Object System.Windows.Controls.ColumnDefinition
        $qtyCol.Width = [System.Windows.GridLength]::Auto
        [void]$g.ColumnDefinitions.Add($qtyCol)

        $r = 0
        for ($j = 0; $j -lt 7; $j++) {
            [void]$g.RowDefinitions.Add((New-RowDef))
            $label = New-Text $script:EquipmentList[$j]
            $label.Margin = [System.Windows.Thickness]::new(0, 6, 16, 6)
            Put $g $label $r 0
            $box = New-QtyBox ([string]$row.EquipValues[$j])
            Put $g $box $r 1
            [void]$script:EquipBoxes.Add(@{ Row = $row; Key = $j; Box = $box })
            $r++
        }

        [void]$g.RowDefinitions.Add((New-RowDef))
        $customName = New-Object System.Windows.Controls.TextBox
        $customName.Text = [string]$row.CustomName
        $customName.ToolTip = 'Custom equipment name'
        $customName.Margin = [System.Windows.Thickness]::new(0, 4, 16, 4)
        Put $g $customName $r 0
        $customQty = New-QtyBox ([string]$row.CustomQty)
        Put $g $customQty $r 1
        [void]$script:EquipBoxes.Add(@{ Row = $row; Key = 'CustomName'; Box = $customName })
        [void]$script:EquipBoxes.Add(@{ Row = $row; Key = 'CustomQty'; Box = $customQty })

        [void]$sp.Children.Add($g)
        $card.Child = $sp
        [void]$script:EquipWrap.Children.Add($card)

        # Render equipment cards immediately; staggered fades cause page lag.
        $card.Opacity = 1
    }
}

function Test-Page1 {
    $name = $script:TxtClient.Text.Trim()
    if ($name -eq '') { Show-Warn 'Client name is required.'; [void]$script:TxtClient.Focus(); return $false }

    $phone = $script:TxtClientPhone.Text.Trim()
    if ($phone -eq '') { Show-Warn 'Client phone number is required.'; [void]$script:TxtClientPhone.Focus(); return $false }
    if (-not (Test-Phone $phone)) {
        Show-Warn 'Client phone number is not valid. Use 6 to 19 digits, optionally starting with +.'
        [void]$script:TxtClientPhone.Focus()
        return $false
    }

    $phone2 = $script:TxtClientPhone2.Text.Trim()
    if ($phone2 -ne '' -and -not (Test-Phone $phone2)) {
        Show-Warn 'Second phone number is not valid. Leave it empty or use 6 to 19 digits.'
        [void]$script:TxtClientPhone2.Focus()
        return $false
    }

    if ($script:DayRows.Count -eq 0) { Show-Warn 'Please add at least one event day.'; return $false }

    foreach ($row in $script:DayRows) {
        if ($null -eq $row -or $null -eq $row.DtDate) { Show-Warn 'An event row is incomplete. Please remove it and add the event day again.'; return $false }
        if ((Get-EventName $row) -eq '') { Show-Warn 'Please enter the event name for every event day.'; return $false }
        $selectedDate = $row.DtDate.SelectedDate
        if ($null -eq $selectedDate) { Show-Warn 'Please select a date for every event day.'; [void]$row.DtDate.Focus(); return $false }
        if ((Get-TimeText $row) -eq '') { Show-Warn 'Please enter the time for every event day.'; return $false }
    }
    return $true
}

function Test-Page2 {
    Save-EquipState
    foreach ($row in $script:DayRows) {
        for ($j = 0; $j -lt 7; $j++) {
            $t = ([string]$row.EquipValues[$j]).Trim()
            if ($t -ne '' -and $t -notmatch '^\d+$') {
                Show-Warn "The quantity for '$($script:EquipmentList[$j])' must be a whole number."
                return $false
            }
        }
        $cq = ([string]$row.CustomQty).Trim()
        if ($cq -ne '' -and $cq -notmatch '^\d+$') { Show-Warn 'The custom equipment quantity must be a whole number.'; return $false }
        if ((Get-IntText $cq) -gt 0 -and ([string]$row.CustomName).Trim() -eq '') {
            Show-Warn 'Please enter the name of the custom equipment.'
            return $false
        }
    }
    return $true
}

function Get-DeliverableSelection {
    $items = New-Object System.Collections.ArrayList
    foreach ($d in $script:DelivDefs) {
        $qty = Get-IntText $d.Qty.Text
        if ($qty -le 0) { continue }
        $label = $d.Label
        $unit = ''
        switch ($d.Kind) {
            'days' {
                if ($qty -gt 1) { $unit = ' Days' } else { $unit = ' Day' }
            }
            'usb' {
                $gb = $d.Extra.Text.Trim()
                if ($gb -match '^\d+$') { $unit = " ($gb GB)" }
                elseif ($gb -ne '') { $unit = " ($gb)" }
            }
            'custom' {
                $label = $d.Extra.Text.Trim()
            }
        }
        [void]$items.Add([pscustomobject]@{ Label = $label; Unit = $unit; Qty = $qty })
    }
    return $items.ToArray()
}

function Update-Remaining {
    $total = ConvertTo-Amount $script:TxtTotal.Text
    $adv = 0.0
    if ($script:TxtAdvance.Text.Trim() -ne '') {
        $a = ConvertTo-Amount $script:TxtAdvance.Text
        if ($null -ne $a) { $adv = $a }
    }
    if ($null -eq $total) { $script:TxtRemaining.Text = '-'; return }
    $script:TxtRemaining.Text = 'Rs. ' + (Format-Money ($total - $adv))
}

function Test-Page3 {
    $total = ConvertTo-Amount $script:TxtTotal.Text
    if ($null -eq $total -or $total -le 0) {
        Show-Warn 'Please enter a valid total amount greater than zero.'
        [void]$script:TxtTotal.Focus()
        return $false
    }
    $advText = $script:TxtAdvance.Text.Trim()
    if ($advText -ne '') {
        $adv = ConvertTo-Amount $advText
        if ($null -eq $adv -or $adv -lt 0) { Show-Warn 'Advance paid must be a valid amount (0 or more).'; return $false }
        if ($adv -gt $total) { Show-Warn 'Advance paid cannot be greater than the total amount.'; return $false }
    }
    foreach ($d in $script:DelivDefs) {
        $t = $d.Qty.Text.Trim()
        if ($t -ne '' -and $t -notmatch '^\d+$') { Show-Warn "The quantity for '$($d.Label)' must be a whole number."; return $false }
        if ((Get-IntText $t) -gt 0 -and $d.Kind -eq 'custom' -and $d.Extra.Text.Trim() -eq '') {
            Show-Warn 'Please enter the name of the custom deliverable.'
            return $false
        }
    }
    if (@(Get-DeliverableSelection).Count -eq 0) {
        Show-Warn 'Please select at least one deliverable with a quantity.'
        return $false
    }
    return $true
}

function Reset-Wizard {
    $script:EditingId = $null
    $script:TxtClient.Clear()
    $script:TxtClientPhone.Clear()
    $script:TxtClientPhone2.Clear()
    $script:DayStack.Children.Clear()
    $script:DayRows.Clear()
    $script:EquipBoxes = New-Object System.Collections.ArrayList
    Add-DayRow
    foreach ($d in $script:DelivDefs) {
        $d.Qty.Clear()
        if ($null -ne $d.Extra) { $d.Extra.Clear() }
    }
    $script:TxtTotal.Clear()
    $script:TxtAdvance.Clear()
    $script:TxtPayNote.Text = $script:DefaultNote
    Update-Remaining
}

function Load-BookingIntoWizard($b) {
    Reset-Wizard
    $script:EditingId = [string]$b.BookingId
    $script:TxtClient.Text = [string]$b.ClientName
    $script:TxtClientPhone.Text = [string]$b.ClientPhone
    $script:TxtClientPhone2.Text = [string]$b.ClientPhone2

    $script:DayStack.Children.Clear()
    $script:DayRows.Clear()
    foreach ($d in @($b.Days)) { Add-DayRow $d }
    if ($script:DayRows.Count -eq 0) { Add-DayRow }

    foreach ($dl in @($b.Deliverables)) {
        $matched = $false
        foreach ($d in $script:DelivDefs) {
            if ($d.Kind -ne 'custom' -and $d.Label -eq [string]$dl.Label) {
                $d.Qty.Text = [string]$dl.Qty
                if ($d.Kind -eq 'usb') {
                    $u = [string]$dl.Unit
                    if ($u -match '^\s*\((.*)\)\s*$') { $d.Extra.Text = ($Matches[1] -replace '\s*GB$', '').Trim() }
                }
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            foreach ($d in $script:DelivDefs) {
                if ($d.Kind -eq 'custom') {
                    $d.Qty.Text = [string]$dl.Qty
                    $d.Extra.Text = [string]$dl.Label
                }
            }
        }
    }

    $script:TxtTotal.Text = ([double]$b.Total).ToString('0.##', $script:Inv)
    $script:TxtAdvance.Text = ([double]$b.Advance).ToString('0.##', $script:Inv)
    $script:TxtPayNote.Text = [string]$b.PaymentNote
    Update-Remaining
}

function Save-Booking {
    $now = Get-Date
    $user = $script:CurrentUser
    $bookings = @(Read-JsonList $script:BookingsFile)

    $isEdit = -not [string]::IsNullOrEmpty($script:EditingId)
    $createdAt = $now.ToString('s', $script:Inv)
    if ($isEdit) {
        $id = $script:EditingId
        $existing = @($bookings | Where-Object { $_.BookingId -eq $id }) | Select-Object -First 1
        if ($null -ne $existing -and $existing.CreatedAt) { $createdAt = [string]$existing.CreatedAt }
        $bookings = @($bookings | Where-Object { $_.BookingId -ne $id })
    }
    else {
        $id = New-BookingId $user.StudioName $now $bookings
    }

    $days = @()
    foreach ($row in $script:DayRows) {
        if ($null -eq $row -or $null -eq $row.DtDate -or $null -eq $row.DtDate.SelectedDate) {
            Show-Warn 'An event date is missing. Please check each event day before saving.'
            return
        }
        $eq = @()
        for ($j = 0; $j -lt 7; $j++) {
            $q = Get-IntText ([string]$row.EquipValues[$j])
            if ($q -gt 0) { $eq += [pscustomobject]@{ Item = $script:EquipmentList[$j]; Qty = $q } }
        }
        $cq = Get-IntText ([string]$row.CustomQty)
        if ($cq -gt 0) {
            $cname = ([string]$row.CustomName).Trim()
            if ($cname -eq '') { $cname = 'Custom' }
            $eq += [pscustomobject]@{ Item = $cname; Qty = $cq }
        }
        $days += [pscustomobject]@{
            Name      = Get-EventName $row
            Date      = ([datetime]$row.DtDate.SelectedDate).ToString('yyyy-MM-dd', $script:Inv)
            Time      = Get-TimeText $row
            Venue     = $row.TxtVenue.Text.Trim()
            Equipment = @($eq)
        }
    }

    $total = ConvertTo-Amount $script:TxtTotal.Text
    $advance = 0.0
    if ($script:TxtAdvance.Text.Trim() -ne '') {
        $a = ConvertTo-Amount $script:TxtAdvance.Text
        if ($null -ne $a) { $advance = $a }
    }

    $booking = [pscustomobject]@{
        BookingId       = $id
        StudioUserId    = $user.Id
        StudioName      = $user.StudioName
        BookedByName    = $user.FullName
        BookedByContact = $user.ContactNumber
        ClientName      = $script:TxtClient.Text.Trim()
        ClientPhone     = $script:TxtClientPhone.Text.Trim()
        ClientPhone2    = $script:TxtClientPhone2.Text.Trim()
        Days            = @($days)
        Deliverables    = @(Get-DeliverableSelection)
        Total           = [double]$total
        Advance         = [double]$advance
        Remaining       = [double]($total - $advance)
        PaymentNote     = $script:TxtPayNote.Text.Trim()
        CreatedAt       = $createdAt
        UpdatedAt       = $(if ($isEdit) { $now.ToString('s', $script:Inv) } else { $null })
    }

    Write-JsonList $script:BookingsFile (@($bookings) + $booking)
    Set-ClipboardText (New-ConfirmationText $booking)
    return $id
}

function Finish-Booking {
    if (-not (Test-Page1)) { Show-Page 'book1'; return }
    if (-not (Test-Page2)) { Build-EquipPage; Show-Page 'book2'; return }
    if (-not (Test-Page3)) { return }
    $id = Save-Booking
    Show-Dlg 'Booking saved' "Booking $id has been saved.`r`n`r`nThe confirmation text has been copied to the clipboard." $false | Out-Null
    Reset-Wizard
    Refresh-Dashboard
    Refresh-Grid
    Set-Nav 'bookings'
    Show-Page 'bookings'
}

# ============================================================
# Bookings table
# ============================================================
function Refresh-Grid {
    $mine = @(Read-JsonList $script:BookingsFile | Where-Object { $_.StudioUserId -eq $script:CurrentUser.Id } | Sort-Object CreatedAt -Descending)
    $q = $script:TxtSearch.Text.Trim()
    $rows = New-Object System.Collections.ArrayList
    $sumTotal = 0.0
    $sumRem = 0.0
    foreach ($b in $mine) {
        if (-not ((Contains-Text ([string]$b.BookingId) $q) -or (Contains-Text ([string]$b.ClientName) $q))) { continue }
        $events = (@($b.Days) | ForEach-Object { '{0} ({1})' -f $_.Name, (Format-DayDate $_.Date) }) -join '; '
        $booked = ''
        try { $booked = ([datetime]$b.CreatedAt).ToString('dd MMM yyyy', $script:Inv) } catch {}
        $sumTotal += [double]$b.Total
        $sumRem   += [double]$b.Remaining
        [void]$rows.Add([pscustomobject]@{
            'Booking ID'     = [string]$b.BookingId
            'Booked On'      = $booked
            'Client Name'    = [string]$b.ClientName
            'Client Contact' = [string]$b.ClientPhone
            'Events'         = $events
            'Total'          = 'Rs. ' + (Format-Money $b.Total)
            'Advance'        = 'Rs. ' + (Format-Money $b.Advance)
            'Remaining'      = 'Rs. ' + (Format-Money $b.Remaining)
            'Booked By'      = [string]$b.BookedByName
        })
    }
    $script:GridBookings.ItemsSource = $rows
    $script:TxtSummary.Text = 'Bookings: {0}      Total: Rs. {1}      Remaining: Rs. {2}' -f $rows.Count, (Format-Money $sumTotal), (Format-Money $sumRem)
}

function Get-BookingById([string]$Id) {
    return (@(Read-JsonList $script:BookingsFile | Where-Object { $_.BookingId -eq $Id }) | Select-Object -First 1)
}

function Copy-Selected {
    $sel = $script:GridBookings.SelectedItem
    if ($null -eq $sel) { Show-Warn 'Please select a booking first.'; return }
    $b = Get-BookingById ([string]$sel.'Booking ID')
    if ($null -eq $b) { Show-Warn 'This booking could not be found.'; return }
    Set-ClipboardText (New-ConfirmationText $b)
    Show-Dlg 'Copied' "Confirmation for $($b.BookingId) copied to the clipboard." $false | Out-Null
}

function Edit-Selected {
    $sel = $script:GridBookings.SelectedItem
    if ($null -eq $sel) { Show-Warn 'Please select a booking first.'; return }
    $b = Get-BookingById ([string]$sel.'Booking ID')
    if ($null -eq $b) { Show-Warn 'This booking could not be found.'; return }
    Load-BookingIntoWizard $b
    Set-Nav 'book1'
    Show-Page 'book1'
}

function Delete-Selected {
    $sel = $script:GridBookings.SelectedItem
    if ($null -eq $sel) { Show-Warn 'Please select a booking first.'; return }
    $id = [string]$sel.'Booking ID'
    $ok = Show-Dlg 'Delete booking' "Delete booking $id?`r`n`r`nThis cannot be undone." $true
    if (-not $ok) { return }
    $rest = @(Read-JsonList $script:BookingsFile | Where-Object { $_.BookingId -ne $id })
    Write-JsonList $script:BookingsFile $rest
    Refresh-Grid
    Refresh-Dashboard
    Show-Dlg 'Deleted' "Booking $id was deleted." $false | Out-Null
}

function Cancel-Wizard {
    Go-Nav 'dash'
}

function Set-LogoImage($HostBorder) {
    $path = Join-Path $script:AppRoot 'logo.png'
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = New-Object System.Uri -ArgumentList $path
        $bmp.CacheOption = 'OnLoad'
        $bmp.EndInit()
        $img = New-Object System.Windows.Controls.Image
        $img.Source = $bmp
        $img.Stretch = 'UniformToFill'
        $HostBorder.Child = $img
        $HostBorder.ClipToBounds = $true
    }
    catch {}
}
# ============================================================
# Startup: load resources, bind named controls, wire events, run
# ============================================================
function Bind-Controls {
    $names = @(
        'Shell', 'TitleBar', 'BtnMin', 'BtnClose',
        'LoginView', 'LoginLogoHost', 'LoginCard', 'BtnTabLogin', 'BtnTabSignup', 'PanelLogin', 'PanelSignup',
        'CboUser', 'PwdLogin', 'BtnLogin', 'BtnDeleteUser', 'TxtSuStudio', 'TxtSuFull', 'TxtSuContact', 'PwdSignup', 'BtnSignup',
        'AppView', 'SideLogoHost', 'BtnNavDash', 'BtnNavNew', 'BtnNavBookings', 'TxtSideUser', 'TxtSideStudio',
        'BtnTheme', 'BtnLogout', 'TxtPageTitle', 'TxtPageSub', 'StepBar', 'Step1', 'Step2', 'Step3',
        'PageDash', 'TxtDashWelcome', 'StatBookings', 'StatTotal', 'StatRemaining', 'BtnDashNew', 'BtnDashView',
        'PageBook1', 'TxtClient', 'TxtClientPhone', 'TxtClientPhone2', 'BtnAddDay', 'DayStack',
        'BtnCancel1', 'BtnNext1',
        'PageBook2', 'EquipWrap', 'BtnCancel2', 'BtnBack2', 'BtnNext2',
        'PageBook3', 'TxtDelFilm', 'TxtDelPhotos', 'TxtDelRaw', 'TxtDelAlbum', 'TxtDelPrint', 'TxtDelUsb', 'TxtDelGb',
        'TxtDelCustomQty', 'TxtDelCustomName', 'TxtTotal', 'TxtAdvance', 'TxtRemaining', 'TxtPayNote',
        'BtnCancel3', 'BtnBack3', 'BtnFinish',
        'PageBookings', 'TxtSearch', 'GridBookings', 'TxtSummary', 'BtnCopy', 'BtnEdit', 'BtnDelete'
    )
    foreach ($n in $names) {
        $control = $script:Win.FindName($n)
        if ($null -eq $control) { throw "Missing control in XAML: $n" }
        Set-Variable -Scope Script -Name $n -Value $control
    }
}

function Set-DelivDefs {
    $script:DelivDefs = @(
        @{ Label = 'Complete Edited Film - Softcopy'; Kind = 'days';   Qty = $script:TxtDelFilm;       Extra = $null },
        @{ Label = 'Complete Photos - Softcopy';      Kind = 'days';   Qty = $script:TxtDelPhotos;     Extra = $null },
        @{ Label = 'Raw Data - Softcopy';             Kind = 'days';   Qty = $script:TxtDelRaw;        Extra = $null },
        @{ Label = 'Indian Album';                    Kind = 'qty';    Qty = $script:TxtDelAlbum;      Extra = $null },
        @{ Label = 'Printed Photo';                   Kind = 'qty';    Qty = $script:TxtDelPrint;      Extra = $null },
        @{ Label = 'USB';                             Kind = 'usb';    Qty = $script:TxtDelUsb;        Extra = $script:TxtDelGb },
        @{ Label = 'Custom Deliverable';              Kind = 'custom'; Qty = $script:TxtDelCustomQty;  Extra = $script:TxtDelCustomName }
    )
}

function Wire-Events {
    $script:BtnMin.Add_Click({ $script:Win.WindowState = 'Minimized' })
    $script:BtnClose.Add_Click({ $script:Win.Close() })
    $script:TitleBar.Add_MouseLeftButtonDown({
        param($s, $e)
        try { $script:Win.DragMove() } catch {}
    })

    # Login and sign up
    $script:BtnTabLogin.Add_Click({ Show-AuthTab $false })
    $script:BtnTabSignup.Add_Click({ Show-AuthTab $true })
    $script:BtnLogin.Add_Click({ Do-Login })
    $script:BtnDeleteUser.Add_Click({ Delete-UserAccount })
    $script:PwdLogin.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Do-Login } })
    $script:BtnSignup.Add_Click({ Do-Signup })
    $script:PwdSignup.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Do-Signup } })

    # Sidebar
    $script:BtnNavDash.Add_Click({ Go-Nav 'dash' })
    $script:BtnNavNew.Add_Click({ Go-Nav 'book1' })
    $script:BtnNavBookings.Add_Click({ Go-Nav 'bookings' })
    $script:BtnLogout.Add_Click({ Do-Logout })
    $script:BtnTheme.Add_Click({
        Set-Theme (-not $script:IsDark) $true
    })

    # Dashboard
    $script:BtnDashNew.Add_Click({ Go-Nav 'book1' })
    $script:BtnDashView.Add_Click({ Go-Nav 'bookings' })

    # Wizard
    $script:BtnAddDay.Add_Click({ Add-DayRow })
    $script:BtnCancel1.Add_Click({ Cancel-Wizard })
    $script:BtnCancel2.Add_Click({ Cancel-Wizard })
    $script:BtnCancel3.Add_Click({ Cancel-Wizard })
    $script:BtnNext1.Add_Click({
        if (Test-Page1) {
            Build-EquipPage
            Show-Page 'book2'
        }
    })
    $script:BtnBack2.Add_Click({
        Save-EquipState
        Show-Page 'book1'
    })
    $script:BtnNext2.Add_Click({
        if (Test-Page2) { Show-Page 'book3' }
    })
    $script:BtnBack3.Add_Click({ Show-Page 'book2' })
    $script:BtnFinish.Add_Click({ Finish-Booking })
    $script:TxtTotal.Add_TextChanged({ Update-Remaining })
    $script:TxtAdvance.Add_TextChanged({ Update-Remaining })

    # Bookings table
    $script:TxtSearch.Add_TextChanged({ Refresh-Grid })
    $script:BtnCopy.Add_Click({ Copy-Selected })
    $script:BtnEdit.Add_Click({ Edit-Selected })
    $script:BtnDelete.Add_Click({ Delete-Selected })
    $script:GridBookings.Add_MouseDoubleClick({ Edit-Selected })
}

Ensure-DataDir

$script:App = New-Object System.Windows.Application
$script:Res = [System.Windows.Markup.XamlReader]::Parse($script:ResourcesXaml)
[void]$script:App.Resources.MergedDictionaries.Add($script:Res)

$script:Win = [System.Windows.Markup.XamlReader]::Parse($script:MainXaml)
Bind-Controls

$script:PageMap = @{
    dash     = $script:PageDash
    book1    = $script:PageBook1
    book2    = $script:PageBook2
    book3    = $script:PageBook3
    bookings = $script:PageBookings
}
$script:EquipBoxes = New-Object System.Collections.ArrayList
Set-DelivDefs

Set-LogoImage $script:LoginLogoHost
Set-LogoImage $script:SideLogoHost
Set-Theme $false $false
Hide-AllPages
Reset-Wizard
Wire-Events
Refresh-Users
Show-AuthTab $false

# Restore the previous profile unless the user explicitly logged out. The session
# contains only a user ID; if that account no longer exists, discard the stale session.
try {
    if (Test-Path -LiteralPath $script:SessionFile) {
        $savedUserId = (Get-Content -LiteralPath $script:SessionFile -Raw -ErrorAction Stop).Trim()
        if (-not [string]::IsNullOrWhiteSpace($savedUserId)) {
            $savedUser = @(Read-JsonList $script:UsersFile | Where-Object { [string]$_.Id -eq $savedUserId } | Select-Object -First 1)
            if ($savedUser.Count -gt 0) {
                $script:CurrentUser = $savedUser[0]
                Enter-App
            } else {
                Remove-Item -LiteralPath $script:SessionFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
} catch {
    # A missing/corrupt session should never prevent the login screen from opening.
    try { Remove-Item -LiteralPath $script:SessionFile -Force -ErrorAction SilentlyContinue } catch { }
}

# Title bar drag and intro animation
$script:Win.Add_Loaded({ Play-Intro })

[void]$script:App.Run($script:Win)
