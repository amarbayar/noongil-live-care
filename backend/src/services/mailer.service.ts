const MAILERSEND_API_URL = 'https://api.mailersend.com/v1/email';

type Permission = 'medications' | 'reminders' | 'schedule' | 'wellness';

const permissionLabels: Record<Permission, string> = {
  medications: 'Medications',
  reminders: 'Custom reminders',
  schedule: 'Check-in schedule',
  wellness: 'Wellness dashboard',
};

export interface CaregiverInvitationEmailInput {
  caregiverEmail: string;
  memberId: string;
  memberName?: string | null;
  permissions: Permission[];
  invitationToken: string;
  expiresAt: string;
  dashboardBaseUrl?: string | null;
}

export interface InvitationEmailResult {
  status: 'sent' | 'skipped';
  inviteUrl: string;
}

function normalizeBaseUrl(url: string): string {
  return url.trim().replace(/\/+$/, '');
}

function getDashboardBaseUrl(fallbackBaseUrl?: string | null): string {
  if (fallbackBaseUrl) return normalizeBaseUrl(fallbackBaseUrl);

  const explicit = process.env.PUBLIC_DASHBOARD_URL;
  if (explicit) return normalizeBaseUrl(explicit);

  const backendBase = process.env.BACKEND_BASE_URL;
  if (backendBase) return normalizeBaseUrl(backendBase);

  return '';
}

export function buildInviteUrl(token: string, fallbackBaseUrl?: string | null): string {
  const baseUrl = getDashboardBaseUrl(fallbackBaseUrl);
  if (!baseUrl) {
    throw new Error('Missing PUBLIC_DASHBOARD_URL or BACKEND_BASE_URL env var');
  }

  return `${baseUrl}/dashboard?invite=${encodeURIComponent(token)}`;
}

function buildPermissionList(permissions: Permission[]): string {
  return permissions.map((permission) => permissionLabels[permission] ?? permission).join(', ');
}

export async function sendCaregiverInvitationEmail(
  input: CaregiverInvitationEmailInput
): Promise<InvitationEmailResult> {
  const inviteUrl = buildInviteUrl(input.invitationToken, input.dashboardBaseUrl);
  const apiKey = process.env.MAILERSEND_API_KEY;
  const fromEmail = process.env.MAILERSEND_FROM_EMAIL;

  if (!apiKey || !fromEmail) {
    return { status: 'skipped', inviteUrl };
  }

  const fromName = process.env.MAILERSEND_FROM_NAME ?? 'Noongil';
  const memberLabel = input.memberName?.trim() || `Noongil member ${input.memberId}`;
  const expiresOn = new Date(input.expiresAt).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'UTC',
  });
  const permissions = buildPermissionList(input.permissions);
  const subject = `${memberLabel} invited you to Noongil Caregiver Dashboard`;
  const text = [
    `${memberLabel} invited you to view selected Noongil caregiver data.`,
    `Shared access: ${permissions}.`,
    `Use this exact email address to sign in and accept the invite: ${input.caregiverEmail}.`,
    `Accept invitation: ${inviteUrl}`,
    `This link expires on ${expiresOn}.`,
  ].join('\n\n');
  const html = `
    <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #111827;">
      <p><strong>${escapeHtml(memberLabel)}</strong> invited you to the Noongil caregiver dashboard.</p>
      <p>Shared access: <strong>${escapeHtml(permissions)}</strong>.</p>
      <p>Sign in with <strong>${escapeHtml(input.caregiverEmail)}</strong> to accept this invitation.</p>
      <p>
        <a href="${inviteUrl}" style="display: inline-block; padding: 12px 18px; border-radius: 999px; background: #2563eb; color: #ffffff; text-decoration: none;">
          Open caregiver invite
        </a>
      </p>
      <p>This invitation expires on ${escapeHtml(expiresOn)}.</p>
    </div>
  `.trim();

  const response = await fetch(MAILERSEND_API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      from: {
        email: fromEmail,
        name: fromName,
      },
      to: [
        {
          email: input.caregiverEmail,
        },
      ],
      subject,
      text,
      html,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`MailerSend request failed (${response.status}): ${body || 'unknown error'}`);
  }

  return { status: 'sent', inviteUrl };
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}
