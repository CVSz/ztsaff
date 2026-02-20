import express from "express"
import cors from "cors"
import bcrypt from "bcrypt"
import jwt from "jsonwebtoken"
import pkg from "pg"

const { Pool } = pkg
const app = express()

const PORT = Number(process.env.PORT || 4000)
const JWT_SECRET = process.env.JWT_SECRET
const DATABASE_URL = process.env.DATABASE_URL
const FRONTEND_ORIGIN = process.env.FRONTEND_ORIGIN

if (!JWT_SECRET) throw new Error("JWT_SECRET is required")
if (!DATABASE_URL) throw new Error("DATABASE_URL is required")

const pool = new Pool({ connectionString: DATABASE_URL })

app.disable("x-powered-by")
app.set("trust proxy", 1)
app.use(express.json({ limit: "200kb" }))
app.use(cors({
  origin: FRONTEND_ORIGIN ? FRONTEND_ORIGIN.split(",").map((v) => v.trim()) : true,
  methods: ["GET", "POST", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"]
}))

app.use((_req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff")
  res.setHeader("X-Frame-Options", "DENY")
  res.setHeader("Referrer-Policy", "no-referrer")
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
  next()
})

const authRateMap = new Map()
function authRateLimit(req, res, next) {
  const key = `${req.ip}:${req.path}`
  const now = Date.now()
  const entry = authRateMap.get(key) ?? { count: 0, startedAt: now }
  if (now - entry.startedAt > 15 * 60 * 1000) {
    authRateMap.set(key, { count: 1, startedAt: now })
    return next()
  }

  if (entry.count >= 30) {
    return res.status(429).json({ error: "Too many requests. Please retry later." })
  }

  entry.count += 1
  authRateMap.set(key, entry)
  next()
}

function normalizeEmail(email = "") {
  return String(email).trim().toLowerCase()
}

function isValidEmail(email = "") {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
}


function safeText(value, max = 255) {
  return String(value ?? "").trim().slice(0, max)
}

function parsePositiveInt(value, fieldName) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed <= 0) {
    const err = new Error(`${fieldName} must be a positive integer`)
    err.status = 400
    throw err
  }
  return parsed
}

function asyncHandler(handler) {
  return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next)
}

app.get("/health", (_req, res) => {
  res.json({ ok: true })
})

app.post("/register", authRateLimit, asyncHandler(async (req, res) => {
  const email = normalizeEmail(req.body.email)
  const password = String(req.body.password ?? "")
  const adminKey = String(req.body.adminKey ?? "").trim()

  if (!email || !password) {
    return res.status(400).json({ error: "email and password are required" })
  }
  if (!isValidEmail(email)) return res.status(400).json({ error: "invalid email format" })
  if (password.length < 8) return res.status(400).json({ error: "password must be at least 8 chars" })

  const role = adminKey && adminKey === process.env.ADMIN_BOOTSTRAP_KEY ? "admin" : "user"
  const hash = await bcrypt.hash(password, 12)

  try {
    await pool.query("INSERT INTO users (email,password_hash,role) VALUES ($1,$2,$3)", [email, hash, role])
  } catch (error) {
    if (error.code === "23505") return res.status(409).json({ error: "email already registered" })
    throw error
  }

  res.json({ message: "Registered", role })
}))

app.post("/login", authRateLimit, asyncHandler(async (req, res) => {
  const email = normalizeEmail(req.body.email)
  const password = String(req.body.password ?? "")

  if (!email || !password) return res.status(400).json({ error: "email and password are required" })
  if (!isValidEmail(email)) return res.status(400).json({ error: "invalid email format" })

  const user = await pool.query("SELECT id, email, role, password_hash FROM users WHERE email=$1", [email])
  if (!user.rows.length) return res.status(401).json({ error: "Invalid credentials" })

  const valid = await bcrypt.compare(password, user.rows[0].password_hash)
  if (!valid) return res.status(401).json({ error: "Invalid credentials" })

  const token = jwt.sign(
    { id: user.rows[0].id, email: user.rows[0].email, role: user.rows[0].role },
    JWT_SECRET,
    { expiresIn: "1d" }
  )

  res.json({ token, role: user.rows[0].role })
}))

function auth(req, res, next) {
  try {
    const header = req.headers.authorization
    if (!header || !header.startsWith("Bearer ")) {
      return res.status(401).json({ error: "Unauthorized" })
    }

    const token = header.slice(7)
    const decoded = jwt.verify(token, JWT_SECRET)
    req.user = decoded
    next()
  } catch (_error) {
    res.status(401).json({ error: "Unauthorized" })
  }
}

function adminOnly(req, res, next) {
  if (req.user.role !== "admin") return res.status(403).json({ error: "Admin only" })
  next()
}

const hooks = [
  "หยุดก่อน! อันนี้โคตรดี",
  "ไม่คิดว่าจะดีขนาดนี้",
  "ใครกำลังเจอปัญหานี้ต้องดู"
]

function generateScript(product) {
  const hook = hooks[Math.floor(Math.random() * hooks.length)]
  return `${hook}\n\nวันนี้จะมารีวิว ${product}\n\nจุดเด่น:\n1. คุณภาพดี\n2. คุ้มราคา\n3. ใช้งานง่าย\n\nลิงก์อยู่หน้าโปรไฟล์\n`
}

function generateVideoPackage(product) {
  const selectedHook = hooks[Math.floor(Math.random() * hooks.length)]
  const title = `${product.title} รีวิวสั้นสำหรับ TikTok Showcase`
  const script = `${selectedHook}\n\nรีวิว ${product.title} จาก TikTok Shop Affiliate\nราคา ${product.price ?? "-"} ${product.currency ?? "THB"}\n\nจุดเด่น 3 ข้อ:\n1) เหมาะกับมือใหม่\n2) ใช้งานจริงได้ทุกวัน\n3) ราคาเข้าถึงง่าย\n\nปิดท้าย: กดดูใน Showcase ได้เลย!`

  const storyboard = [
    { scene: 1, duration_sec: 3, shot: "close-up product", text: selectedHook },
    { scene: 2, duration_sec: 5, shot: "problem -> solution", text: `ปัญหาที่แก้ได้ด้วย ${product.title}` },
    { scene: 3, duration_sec: 6, shot: "benefits list", text: "คุณภาพดี | คุ้มราคา | ใช้งานง่าย" },
    { scene: 4, duration_sec: 4, shot: "cta", text: "กดเข้าชมใน TikTok Showcase" }
  ]

  const hashtags = "#tiktokshop #affiliate #รีวิวของดี #ป้ายยาของดี #tiktokshowcase"
  return { title, hook: selectedHook, script, storyboard, hashtags }
}

app.get("/me", auth, asyncHandler(async (req, res) => {
  const me = await pool.query("SELECT id, email, role, plan, created_at FROM users WHERE id=$1", [req.user.id])
  res.json(me.rows[0] ?? null)
}))

app.get("/user/dashboard", auth, asyncHandler(async (req, res) => {
  const [products, videoJobs, uploads, activeRental] = await Promise.all([
    pool.query("SELECT COUNT(*)::int AS count FROM products WHERE user_id=$1", [req.user.id]),
    pool.query("SELECT COUNT(*)::int AS count FROM video_jobs WHERE user_id=$1", [req.user.id]),
    pool.query("SELECT COUNT(*)::int AS count FROM showcase_uploads WHERE user_id=$1", [req.user.id]),
    pool.query(
      `SELECT ur.*, rp.code, rp.name, rp.max_video_jobs
       FROM user_rentals ur
       JOIN rental_plans rp ON rp.id = ur.plan_id
       WHERE ur.user_id=$1 AND ur.status='active'
       ORDER BY ur.created_at DESC
       LIMIT 1`,
      [req.user.id]
    )
  ])

  res.json({
    stats: {
      product_count: products.rows[0].count,
      video_job_count: videoJobs.rows[0].count,
      upload_count: uploads.rows[0].count
    },
    active_rental: activeRental.rows[0] ?? null
  })
}))

app.get("/rent/plans", auth, asyncHandler(async (_req, res) => {
  const data = await pool.query("SELECT code, name, monthly_price, max_video_jobs, perks FROM rental_plans WHERE active=TRUE ORDER BY monthly_price ASC")
  res.json(data.rows)
}))

app.post("/rent/subscribe", auth, asyncHandler(async (req, res) => {
  const planCode = safeText(req.body.planCode, 50)
  const months = parsePositiveInt(req.body.months ?? 1, "months")

  if (!planCode) return res.status(400).json({ error: "planCode is required" })
  if (months > 24) return res.status(400).json({ error: "months must be <= 24" })

  const plan = await pool.query("SELECT * FROM rental_plans WHERE code=$1 AND active=TRUE", [planCode])
  if (!plan.rows.length) return res.status(404).json({ error: "Plan not found" })

  const selected = plan.rows[0]
  const totalPrice = Number(selected.monthly_price) * months

  await pool.query("UPDATE user_rentals SET status='expired' WHERE user_id=$1 AND status='active'", [req.user.id])

  const rental = await pool.query(
    `INSERT INTO user_rentals (user_id, plan_id, months, total_price, status, starts_at, ends_at)
     VALUES ($1,$2,$3,$4,'active',NOW(), NOW() + ($3 || ' month')::INTERVAL)
     RETURNING *`,
    [req.user.id, selected.id, months, totalPrice]
  )

  await pool.query("UPDATE users SET plan=$1 WHERE id=$2", [selected.code, req.user.id])
  res.json({ message: "Rent plan subscribed", rental: rental.rows[0], plan: selected })
}))

app.get("/me/rentals", auth, asyncHandler(async (req, res) => {
  const data = await pool.query(
    `SELECT ur.*, rp.code, rp.name, rp.monthly_price, rp.max_video_jobs
     FROM user_rentals ur
     JOIN rental_plans rp ON rp.id = ur.plan_id
     WHERE ur.user_id=$1
     ORDER BY ur.created_at DESC`,
    [req.user.id]
  )
  res.json(data.rows)
}))

app.post("/generate", auth, asyncHandler(async (req, res) => {
  const product = safeText(req.body.product, 255)
  const category = safeText(req.body.category, 100)
  if (!product) return res.status(400).json({ error: "product is required" })

  const script = generateScript(product)
  await pool.query("INSERT INTO scripts (user_id,product_name,category,content) VALUES ($1,$2,$3,$4)", [
    req.user.id,
    product,
    category || "general",
    script
  ])
  res.json({ script })
}))

app.get("/my-scripts", auth, asyncHandler(async (req, res) => {
  const data = await pool.query("SELECT * FROM scripts WHERE user_id=$1 ORDER BY created_at DESC", [req.user.id])
  res.json(data.rows)
}))

app.post("/product-feed/import", auth, asyncHandler(async (req, res) => {
  const feedName = safeText(req.body.feedName || "My TikTok Feed", 255)
  const products = Array.isArray(req.body.products) ? req.body.products : []

  if (products.length === 0) return res.status(400).json({ error: "products array is required" })
  if (products.length > 200) return res.status(400).json({ error: "products array too large (max 200)" })

  const feed = await pool.query("INSERT INTO product_feeds (user_id, feed_name) VALUES ($1,$2) RETURNING *", [
    req.user.id,
    feedName
  ])

  const inserted = []
  for (const p of products) {
    if (!(p?.title && (p.product_id || p.id))) continue

    const title = safeText(p.title, 255)
    const category = safeText(p.category || "general", 100)
    const productId = safeText(p.product_id ?? p.id, 128)
    const currency = safeText(p.currency || "THB", 12)
    const productUrl = safeText(p.product_url || "", 2048) || null
    const imageUrl = safeText(p.image_url || "", 2048) || null
    const price = typeof p.price === "number" ? p.price : null

    const row = await pool.query(
      `INSERT INTO products
      (feed_id, user_id, product_id, title, category, price, currency, product_url, image_url, raw_payload)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
      RETURNING *`,
      [feed.rows[0].id, req.user.id, productId, title, category, price, currency, productUrl, imageUrl, JSON.stringify(p)]
    )
    inserted.push(row.rows[0])
  }

  res.json({ feed: feed.rows[0], inserted_count: inserted.length, products: inserted })
}))

app.get("/products", auth, asyncHandler(async (req, res) => {
  const data = await pool.query("SELECT * FROM products WHERE user_id=$1 ORDER BY created_at DESC", [req.user.id])
  res.json(data.rows)
}))

app.post("/video/generate-from-feed", auth, asyncHandler(async (req, res) => {
  const productDbId = parsePositiveInt(req.body.productDbId, "productDbId")
  const ttsVoice = safeText(req.body.ttsVoice || "th_female_1", 50)

  const product = await pool.query("SELECT * FROM products WHERE id=$1 AND user_id=$2", [productDbId, req.user.id])
  if (!product.rows.length) return res.status(404).json({ error: "Product not found" })

  const activeRental = await pool.query(
    `SELECT ur.*, rp.max_video_jobs
     FROM user_rentals ur
     JOIN rental_plans rp ON rp.id = ur.plan_id
     WHERE ur.user_id=$1 AND ur.status='active'
     ORDER BY ur.created_at DESC
     LIMIT 1`,
    [req.user.id]
  )

  if (activeRental.rows.length) {
    const maxJobs = activeRental.rows[0].max_video_jobs
    const count = await pool.query("SELECT COUNT(*)::int AS count FROM video_jobs WHERE user_id=$1", [req.user.id])
    if (count.rows[0].count >= maxJobs) {
      return res.status(403).json({ error: "Plan limit reached. Please rent a higher plan." })
    }
  }

  const pack = generateVideoPackage(product.rows[0])
  const saved = await pool.query(
    `INSERT INTO video_jobs
    (user_id, product_ref, status, title, hook, script, storyboard, hashtags, tts_voice)
    VALUES ($1,$2,'generated',$3,$4,$5,$6,$7,$8)
    RETURNING *`,
    [req.user.id, productDbId, pack.title, pack.hook, pack.script, JSON.stringify(pack.storyboard), pack.hashtags, ttsVoice]
  )

  res.json(saved.rows[0])
}))

app.get("/video-jobs", auth, asyncHandler(async (req, res) => {
  const data = await pool.query("SELECT * FROM video_jobs WHERE user_id=$1 ORDER BY created_at DESC", [req.user.id])
  res.json(data.rows)
}))

app.post("/showcase/upload", auth, asyncHandler(async (req, res) => {
  const videoJobId = parsePositiveInt(req.body.videoJobId, "videoJobId")
  const caption = safeText(req.body.caption || "", 500)

  const video = await pool.query("SELECT id FROM video_jobs WHERE id=$1 AND user_id=$2", [videoJobId, req.user.id])
  if (!video.rows.length) return res.status(404).json({ error: "Video job not found" })

  const showcaseVideoId = `showcase_${Date.now()}`
  const publishUrl = `https://www.tiktok.com/t/${showcaseVideoId}`

  const upload = await pool.query(
    `INSERT INTO showcase_uploads
    (user_id, video_job_id, status, showcase_video_id, publish_url, payload)
    VALUES ($1,$2,'uploaded',$3,$4,$5)
    RETURNING *`,
    [req.user.id, videoJobId, showcaseVideoId, publishUrl, JSON.stringify({ caption })]
  )

  res.json({ message: "Uploaded to TikTok Showcase (simulated)", upload: upload.rows[0] })
}))

app.get("/showcase/uploads", auth, asyncHandler(async (req, res) => {
  const data = await pool.query("SELECT * FROM showcase_uploads WHERE user_id=$1 ORDER BY created_at DESC", [req.user.id])
  res.json(data.rows)
}))

app.get("/admin/dashboard", auth, adminOnly, asyncHandler(async (_req, res) => {
  const [users, activeRentals, jobs, uploads] = await Promise.all([
    pool.query("SELECT COUNT(*)::int AS count FROM users"),
    pool.query("SELECT COUNT(*)::int AS count FROM user_rentals WHERE status='active'"),
    pool.query("SELECT COUNT(*)::int AS count FROM video_jobs"),
    pool.query("SELECT COUNT(*)::int AS count FROM showcase_uploads")
  ])

  res.json({
    total_users: users.rows[0].count,
    active_rentals: activeRentals.rows[0].count,
    total_video_jobs: jobs.rows[0].count,
    total_uploads: uploads.rows[0].count
  })
}))

app.get("/admin/users", auth, adminOnly, asyncHandler(async (_req, res) => {
  const data = await pool.query("SELECT id, email, role, plan, created_at FROM users ORDER BY created_at DESC")
  res.json(data.rows)
}))

app.get("/admin/rentals", auth, adminOnly, asyncHandler(async (_req, res) => {
  const data = await pool.query(
    `SELECT ur.*, u.email, rp.code, rp.name
     FROM user_rentals ur
     JOIN users u ON u.id = ur.user_id
     JOIN rental_plans rp ON rp.id = ur.plan_id
     ORDER BY ur.created_at DESC`
  )
  res.json(data.rows)
}))

app.post("/admin/users/:id/role", auth, adminOnly, asyncHandler(async (req, res) => {
  const id = parsePositiveInt(req.params.id, "id")
  const role = safeText(req.body.role, 20)
  if (!["admin", "user"].includes(role)) return res.status(400).json({ error: "role must be admin or user" })

  const updated = await pool.query("UPDATE users SET role=$1 WHERE id=$2 RETURNING id,email,role,plan", [role, id])
  if (!updated.rows.length) return res.status(404).json({ error: "User not found" })
  res.json(updated.rows[0])
}))

app.use((error, _req, res, _next) => {
  const status = error.status || 500
  if (status >= 500) {
    console.error("Unhandled error:", error)
  }
  res.status(status).json({ error: status >= 500 ? "Internal server error" : error.message })
})

app.listen(PORT, () => console.log(`Backend running on ${PORT}`))
