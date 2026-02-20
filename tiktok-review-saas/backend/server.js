import express from "express"
import cors from "cors"
import bcrypt from "bcrypt"
import jwt from "jsonwebtoken"
import pkg from "pg"

const { Pool } = pkg
const app = express()
app.use(cors())
app.use(express.json())

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
})

app.get("/health", (_req, res) => {
  res.json({ ok: true })
})

app.post("/register", async (req, res) => {
  try {
    const { email, password, adminKey } = req.body
    if (!email || !password) return res.status(400).json({ error: "email and password are required" })

    const role = adminKey && adminKey === process.env.ADMIN_BOOTSTRAP_KEY ? "admin" : "user"
    const hash = await bcrypt.hash(password, 10)
    await pool.query("INSERT INTO users (email,password_hash,role) VALUES ($1,$2,$3)", [email, hash, role])
    res.json({ message: "Registered", role })
  } catch (error) {
    res.status(400).json({ error: "Registration failed", details: error.message })
  }
})

app.post("/login", async (req, res) => {
  const { email, password } = req.body
  const user = await pool.query("SELECT * FROM users WHERE email=$1", [email])
  if (!user.rows.length) return res.status(400).json({ error: "User not found" })

  const valid = await bcrypt.compare(password, user.rows[0].password_hash)
  if (!valid) return res.status(400).json({ error: "Invalid password" })

  const token = jwt.sign(
    { id: user.rows[0].id, email: user.rows[0].email, role: user.rows[0].role },
    process.env.JWT_SECRET,
    { expiresIn: "1d" }
  )

  res.json({ token, role: user.rows[0].role })
})

function auth(req, res, next) {
  try {
    const header = req.headers.authorization
    if (!header) return res.status(401).json({ error: "No token" })

    const token = header.split(" ")[1]
    const decoded = jwt.verify(token, process.env.JWT_SECRET)
    req.user = decoded
    next()
  } catch (_error) {
    res.status(401).json({ error: "Invalid token" })
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

app.get("/me", auth, async (req, res) => {
  const me = await pool.query("SELECT id, email, role, plan, created_at FROM users WHERE id=$1", [req.user.id])
  res.json(me.rows[0])
})

app.get("/user/dashboard", auth, async (req, res) => {
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
})

app.get("/rent/plans", auth, async (_req, res) => {
  const data = await pool.query("SELECT * FROM rental_plans WHERE active=TRUE ORDER BY monthly_price ASC")
  res.json(data.rows)
})

app.post("/rent/subscribe", auth, async (req, res) => {
  const { planCode, months = 1 } = req.body
  if (!planCode) return res.status(400).json({ error: "planCode is required" })
  if (Number(months) <= 0) return res.status(400).json({ error: "months must be > 0" })

  const plan = await pool.query("SELECT * FROM rental_plans WHERE code=$1 AND active=TRUE", [planCode])
  if (!plan.rows.length) return res.status(404).json({ error: "Plan not found" })

  const selected = plan.rows[0]
  const totalPrice = Number(selected.monthly_price) * Number(months)

  await pool.query("UPDATE user_rentals SET status='expired' WHERE user_id=$1 AND status='active'", [req.user.id])

  const rental = await pool.query(
    `INSERT INTO user_rentals (user_id, plan_id, months, total_price, status, starts_at, ends_at)
     VALUES ($1,$2,$3,$4,'active',NOW(), NOW() + ($3 || ' month')::INTERVAL)
     RETURNING *`,
    [req.user.id, selected.id, Number(months), totalPrice]
  )

  await pool.query("UPDATE users SET plan=$1 WHERE id=$2", [selected.code, req.user.id])
  res.json({ message: "Rent plan subscribed", rental: rental.rows[0], plan: selected })
})

app.get("/me/rentals", auth, async (req, res) => {
  const data = await pool.query(
    `SELECT ur.*, rp.code, rp.name, rp.monthly_price, rp.max_video_jobs
     FROM user_rentals ur
     JOIN rental_plans rp ON rp.id = ur.plan_id
     WHERE ur.user_id=$1
     ORDER BY ur.created_at DESC`,
    [req.user.id]
  )
  res.json(data.rows)
})

app.post("/generate", auth, async (req, res) => {
  const { product, category } = req.body
  const script = generateScript(product)
  await pool.query("INSERT INTO scripts (user_id,product_name,category,content) VALUES ($1,$2,$3,$4)", [
    req.user.id,
    product,
    category,
    script
  ])
  res.json({ script })
})

app.get("/my-scripts", auth, async (req, res) => {
  const data = await pool.query("SELECT * FROM scripts WHERE user_id=$1 ORDER BY created_at DESC", [req.user.id])
  res.json(data.rows)
})

app.post("/product-feed/import", auth, async (req, res) => {
  const { feedName = "My TikTok Feed", products = [] } = req.body
  if (!Array.isArray(products) || products.length === 0) {
    return res.status(400).json({ error: "products array is required" })
  }

  const feed = await pool.query("INSERT INTO product_feeds (user_id, feed_name) VALUES ($1,$2) RETURNING *", [
    req.user.id,
    feedName
  ])

  const inserted = []
  for (const p of products) {
    if (!(p.title && (p.product_id || p.id))) continue
    const row = await pool.query(
      `INSERT INTO products
      (feed_id, user_id, product_id, title, category, price, currency, product_url, image_url, raw_payload)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
      RETURNING *`,
      [
        feed.rows[0].id,
        req.user.id,
        p.product_id ?? p.id,
        p.title,
        p.category ?? "general",
        p.price ?? null,
        p.currency ?? "THB",
        p.product_url ?? null,
        p.image_url ?? null,
        JSON.stringify(p)
      ]
    )
    inserted.push(row.rows[0])
  }

  res.json({ feed: feed.rows[0], inserted_count: inserted.length, products: inserted })
})

app.get("/products", auth, async (req, res) => {
  const data = await pool.query("SELECT * FROM products WHERE user_id=$1 ORDER BY created_at DESC", [req.user.id])
  res.json(data.rows)
})

app.post("/video/generate-from-feed", auth, async (req, res) => {
  const { productDbId, ttsVoice = "th_female_1" } = req.body
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
})

app.get("/video-jobs", auth, async (req, res) => {
  const data = await pool.query("SELECT * FROM video_jobs WHERE user_id=$1 ORDER BY created_at DESC", [req.user.id])
  res.json(data.rows)
})

app.post("/showcase/upload", auth, async (req, res) => {
  const { videoJobId, caption = "" } = req.body
  const video = await pool.query("SELECT * FROM video_jobs WHERE id=$1 AND user_id=$2", [videoJobId, req.user.id])
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

  res.json({
    message: "Uploaded to TikTok Showcase (simulated)",
    upload: upload.rows[0]
  })
})

app.get("/showcase/uploads", auth, async (req, res) => {
  const data = await pool.query("SELECT * FROM showcase_uploads WHERE user_id=$1 ORDER BY created_at DESC", [req.user.id])
  res.json(data.rows)
})

app.get("/admin/dashboard", auth, adminOnly, async (_req, res) => {
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
})

app.get("/admin/users", auth, adminOnly, async (_req, res) => {
  const data = await pool.query(
    "SELECT id, email, role, plan, created_at FROM users ORDER BY created_at DESC"
  )
  res.json(data.rows)
})

app.get("/admin/rentals", auth, adminOnly, async (_req, res) => {
  const data = await pool.query(
    `SELECT ur.*, u.email, rp.code, rp.name
     FROM user_rentals ur
     JOIN users u ON u.id = ur.user_id
     JOIN rental_plans rp ON rp.id = ur.plan_id
     ORDER BY ur.created_at DESC`
  )
  res.json(data.rows)
})

app.post("/admin/users/:id/role", auth, adminOnly, async (req, res) => {
  const { id } = req.params
  const { role } = req.body
  if (!["admin", "user"].includes(role)) return res.status(400).json({ error: "role must be admin or user" })

  const updated = await pool.query("UPDATE users SET role=$1 WHERE id=$2 RETURNING id,email,role,plan", [role, id])
  if (!updated.rows.length) return res.status(404).json({ error: "User not found" })
  res.json(updated.rows[0])
})

app.listen(4000, () => console.log("Backend running on 4000"))
