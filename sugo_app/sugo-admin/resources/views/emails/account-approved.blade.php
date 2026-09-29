{{--
  The approval email.

  Table layout and inline styles, like the OTP template in
  `supabase/templates/magic_link.html`: Gmail and Outlook strip <style> blocks
  and do not implement flexbox, so anything cleverer renders as a stack of
  unstyled text in exactly the clients most people read mail in.

  Colours are the SUGO tokens by value rather than by name - an email cannot
  import `app_colors.dart`, and there is no Blade equivalent of it here.
--}}
<table width="100%" cellpadding="0" cellspacing="0" border="0"
       style="background:#F5F7FA;padding:32px 12px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <tr>
    <td align="center">
      <table width="100%" cellpadding="0" cellspacing="0" border="0"
             style="max-width:520px;background:#FFFFFF;border-radius:20px;border:1px solid #E3E8EF;">

        <tr>
          <td style="padding:32px 32px 0 32px;">
            <p style="margin:0;font-size:13px;font-weight:700;letter-spacing:1.5px;color:#0663C4;text-transform:uppercase;">
              SUGO
            </p>
            <h1 style="margin:14px 0 0 0;font-size:23px;font-weight:800;color:#10233F;">
              You&rsquo;re approved, {{ $name }}
            </h1>
          </td>
        </tr>

        <tr>
          <td style="padding:16px 32px 0 32px;">
            <p style="margin:0;font-size:14.5px;line-height:1.6;color:#10233F;">
              A member of our team has reviewed your ID and your account is now
              active. You can sign in to the SUGO app straight away.
            </p>

            <p style="margin:16px 0 0 0;font-size:14.5px;line-height:1.6;color:#5F6E84;">
              @if ($isTechnician)
                Turn on your availability from the home tab and you will start
                receiving job offers matched to the devices and brands you
                declared. You only see jobs you are actually qualified for.
              @else
                You can post your first repair right away. We score every
                available technician against your device and your location, and
                show you the best three with the reasons for each.
              @endif
            </p>
          </td>
        </tr>

        <tr>
          <td style="padding:24px 32px;">
            <table cellpadding="0" cellspacing="0" border="0"
                   style="background:#EAF5FF;border-radius:16px;width:100%;">
              <tr>
                <td style="padding:18px 20px;">
                  <p style="margin:0;font-size:13px;font-weight:700;color:#054FA0;">
                    Sign in with the email and password you registered with
                  </p>
                  <p style="margin:6px 0 0 0;font-size:12.5px;line-height:1.5;color:#5F6E84;">
                    Nothing has changed about your login. If you have forgotten
                    your password, use &ldquo;Forgot password&rdquo; on the sign-in screen.
                  </p>
                  {{-- Matches the one-time setup screen the app shows on this
                       first sign-in (ProfileSetupScreen.firstRun). Telling them
                       now means it reads as expected, not as a surprise gate. --}}
                  <p style="margin:10px 0 0 0;font-size:12.5px;line-height:1.5;color:#5F6E84;">
                    @if ($isTechnician)
                      The first time you sign in, we will ask for a profile photo
                      and your workshop location. It takes a minute, and you can
                      skip it and finish later from the Profile tab.
                    @else
                      The first time you sign in, we will ask for a profile photo
                      so technicians recognise you. You can skip it and add one
                      later from the Profile tab.
                    @endif
                  </p>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <tr>
          <td style="padding:0 32px 32px 32px;">
            <p style="margin:0;font-size:12.5px;line-height:1.55;color:#5F6E84;">
              You are receiving this because you completed a SUGO registration
              and a reviewer approved it. If that was not you, reply to this
              email and we will look into it.
            </p>
          </td>
        </tr>

      </table>

      <p style="margin:20px 0 0 0;font-size:11.5px;color:#5F6E84;">
        SUGO &middot; Ask. Book. Done.
      </p>
    </td>
  </tr>
</table>
