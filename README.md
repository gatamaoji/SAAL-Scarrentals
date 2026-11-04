# Car Rental Management System (CRMS)

Web-based rental management for a car rental business: bookings, availability calendar, Gantt fleet timeline, check-out / check-in, invoices, deposits, maintenance, Power BI-style dashboard, reports, users with editable privileges, and a built-in SOP.

- **Hosting:** GitHub Pages (free, static).
- **Shared database:** Supabase (free tier, PostgreSQL), protected by row-level security.
- **Many users at once:** every change syncs live to everyone signed in; the top bar shows who is online.

> **Two modes**
> - **Local mode** — `config.js` left empty. Data stays in one browser on one computer. Good for a demo.
> - **Shared mode** — `config.js` filled in. All staff, any computer, same data, at the same time.

---

## Files

| File | Purpose |
|---|---|
| `index.html` | The whole application |
| `config.js` | Connection to your Supabase project (fill in) |
| `supabase/schema.sql` | Creates the database, security rules and functions |
| `docs/architecture.html` | Database architecture blueprint |
| `.gitignore` | Stops backups / exports (customer data) being committed |

---

## Your live project (already created)
- Supabase project: **car-rental-system** · region **Sydney** · ref `kznbodwcxcyaxwlfbuih`
- Database schema, security rules and live sync are **installed**; `config.js` is **already filled in**.
- Remaining steps: **1.3** (turn *Confirm email* off), **3** (GitHub Pages) and **4** (first sign-in).
- Dashboard: https://supabase.com/dashboard/project/kznbodwcxcyaxwlfbuih

## Setup — about 20 minutes (for a new project)

### 1. Create the shared database (Supabase)
1. Sign up at **supabase.com** → **New project**.
   - Region: **Sydney** (closest to Vanuatu).
   - Save the database password somewhere safe.
2. **SQL Editor → New query** → paste all of `supabase/schema.sql` → **Run**.
   - Expect "Success". It is safe to run again.
3. **Authentication → Sign In / Providers → Email**:
   - **Enable Email provider**: ON
   - **Confirm email**: **OFF** (staff accounts are created by your administrator, not by email links)
   - **Allow new users to sign up**: ON (needed for the administrator to create staff accounts)
4. **Project Settings → API** → copy:
   - **Project URL**
   - **anon public** key
   - ⚠️ Never use the `service_role` key anywhere in this project.

### 2. Connect the app
Edit `config.js`:
```js
window.CRMS_CONFIG = {
  supabaseUrl: 'https://YOUR-PROJECT.supabase.co',
  supabaseAnonKey: 'YOUR-ANON-PUBLIC-KEY',
  loginDomain: 'example.com'   // or your own domain, e.g. 'islandcarrentals.vu'
};
```
- Usernames are stored internally as `username@loginDomain`. No email is ever sent.
- Choose `loginDomain` once and do not change it later (existing users would stop matching).

### 3. Publish on GitHub Pages
1. GitHub → **New repository** (e.g. `car-rental-system`) → upload all files in this folder → **Commit**.
2. Repository **Settings → Pages** → Source: **Deploy from a branch** → Branch: `main` / `/ (root)` → **Save**.
3. After ~1 minute the site is live at `https://YOUR-GITHUB-NAME.github.io/car-rental-system/`.

### 4. First sign-in — do this straight away
1. Open the site → the **First-time setup** form appears.
2. Enter your name, username and a strong password (8+ characters).
3. Optional: tick **Load sample data** to explore (clear it later in *Settings & data*).
4. Sign in → **Users & privileges** → **+ Add user** for each staff member.
   - Each new user can sign in immediately, from any computer, at the same web address.
   - Everyone signed in sees new users, bookings and changes live.

> The first-time setup only works while the database has no users. Complete it immediately after publishing.

---

## Moving existing local data into the shared database
1. In the **old** local copy: *Settings & data* → **Export backup (.json)**.
2. In the **shared** site, signed in as administrator: *Settings & data* → **Restore from backup**.
3. Records are uploaded for everyone. Users and passwords are **not** copied — create staff accounts in the shared site.

---

## Security — what protects your data
- **Login:** Supabase Auth (bcrypt-hashed passwords, session tokens). Sessions end when the browser closes or after inactivity.
- **Row-level security (enforced by the database, not just the screen):**
  - Only **active** staff accounts can read or write any record.
  - Unknown sign-ups and disabled users see nothing.
  - Users, roles and privileges: writable only by roles with **Manage users**.
  - Settings and rate card: writable only by roles with **Edit settings**.
  - Audit log: **append-only** — cannot be edited or deleted.
  - Records are never physically deleted (soft delete).
- **Screen-level privileges** (bookings, check-out, payments, reports, etc.) hide screens and buttons per role.
- The `anon` key in `config.js` is public by design; it grants nothing without a valid staff sign-in.

**Before real customer data:**
- Use strong passwords; remove staff accounts the day people leave.
- Never commit backups, CSV or SQL exports to GitHub (`.gitignore` blocks the common ones).
- Keep a weekly backup off the office computer.
- Supabase free projects pause after 7 days without activity — upgrade to Pro for a live business, or open the site at least weekly.
- Check that your privacy obligations for customer ID/licence data are met.

---

## Known limits
- If two people edit the **same** record at the same moment, the last save wins.
- Document numbers are unique across users but can skip numbers (each computer reserves a small block).
- Two users allocating the same vehicle within the same second is not blocked by the database; live sync makes this very unlikely, and the availability screens show the clash.
- The whole database loads into the browser at sign-in. Fine for a small to medium fleet (tens of thousands of records); a larger operation should move to the full server design in `docs/architecture.html`.

---

## Support checklist
| Problem | Fix |
|---|---|
| "Cannot reach the shared database" | Check internet; check URL and anon key in `config.js` |
| Setup form says sign-in failed | Turn **Confirm email** OFF in Supabase (step 1.3) |
| New user created but cannot sign in | Same — **Confirm email** must be OFF |
| "Email address is invalid" when creating users | Set `loginDomain` to a real domain you own |
| Everyone sees nothing after sign-in | Run `supabase/schema.sql` again; check the user is **Active** |
| Site shows "Local mode" | `config.js` is empty or not uploaded |
