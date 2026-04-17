# 12 Days to Deming

An active-learning course based on the teachings of Dr. W. Edwards Deming, developed by Henry R. Neave.

## 📚 About This Course

**12 Days to Deming** is a comprehensive, interactive learning experience designed to introduce students to the profound wisdom and practical insights of Dr. W. Edwards Deming. Unlike traditional distance learning, this course emphasizes **active learning**—where students engage with material through immediate activities and exercises rather than passive reading.

### What Makes This Course Special

- **Active Learning Approach**: Activities are integrated throughout the learning process, not just at the end
- **Progressive Structure**: 12 "days" of learning, each designed as a full working day (6-8 hours)
- **Hands-on Projects**: Two substantial projects that help students apply Deming's principles
- **Interactive Elements**: Built-in exercises, reflections, and practical applications
- **Comprehensive Coverage**: From basic concepts to advanced applications of Deming's System of Profound Knowledge

## 🎯 Who This Course Is For

- **Managers and Leaders** seeking to improve organizational performance
- **Quality Professionals** wanting to understand Deming's approach to quality management
- **Students** studying management, operations, or quality improvement
- **Anyone** interested in learning about systems thinking and continuous improvement
- **Self-learners** or **study groups** (2-12 people) working together

## 📖 Course Structure

The course is organized into 12 "days" of learning:

- **Day 1**: The Overture - Introduction and overview
- **Days 2-3**: Foundation concepts and principles
- **Days 4-5**: First Project - Practical application
- **Days 6-9**: Deep dive into Deming's System of Profound Knowledge
- **Days 10-11**: Second Project - Advanced application (the climax of the course)
- **Day 12**: Integration and next steps

Each day includes:
- Reading materials with embedded activities
- Interactive exercises and reflections
- Practical applications of concepts
- Time management guidance with clock indicators

## 🚀 Getting Started

### Prerequisites
- No prior knowledge of Deming's work required
- Basic understanding of organizational management helpful
- Commitment to active participation and reflection

### Time Commitment
- **Recommended**: 1-2 days per week over 6-12 weeks
- **Minimum**: 1 day per week (to maintain continuity)
- **Maximum**: 3 days per week (intensive study)
- **Per session**: 6-8 hours per "day"

### Study Options
1. **Self-study**: Work through the material independently
2. **Small groups**: 2-4 people working together
3. **Medium groups**: 5-12 people with self-study + discussion meetings

## 📥 Accessing the Course Material

### Interactive Online Version (Work in Progress)
- **Live Course**: [deming.leedurbin.co.nz](https://deming.leedurbin.co.nz) - The interactive version with embedded activities and exercises

**Current Status**: All 12 days are now fully converted from the original PDF format into the interactive experience. Content refinements, accessibility improvements, and activity polish are ongoing.

**Enhanced Features in the Online Version:**
- **Interactive Clock Indicators**: Built-in timing guidance to help you pace your study sessions
- **Embedded Activities**: Interactive exercises and reflections integrated directly into the reading flow
- **Progress Tracking**: Visual indicators to help you monitor your advancement through the material
- **Responsive Design**: Optimized for desktop, tablet, and mobile devices
- **Search and Navigation**: Easy content discovery and cross-referencing
- **Print-Friendly**: Clean, formatted output for printing or PDF generation
- **Accessibility**: Skip-link, optional dyslexia-friendly font, ARIA-labelled interactive elements, and reduced-motion support — see the [Accessibility](#-accessibility) section below for the full list

### Complete PDF Version
The full course material is available as free PDF downloads from several sources:

- **[New Zealand Organisation for Quality (NZOQ)](https://www.nzoq.org.nz/12-days-to-deming)**: Complete course with individual PDF files for each day and workbooks
- **Other Quality Organizations**: Various quality management organizations worldwide offer the course materials

The PDF version includes:
- Welcome booklet and course introduction
- Individual day materials (Days 1-12)
- Workbooks for hands-on activities
- Appendix and reference materials
- Optional extras and additional resources

**Note**: The PDF version contains the complete 12-day course and is the most comprehensive option currently available.

### Content Integrity
**Important Note**: Both the interactive online version and PDF versions preserve Dr. Neave's original content exactly as he wrote it. No changes have been made to his teachings, examples, or explanations. The enhancements focus solely on presentation and user experience—maintaining the authentic learning journey and pedagogical flow that Dr. Neave carefully crafted. The interactive elements are designed to support and amplify his original vision, not replace or modify it.

### Study Groups
- **Online Study Groups**: The Geelong Quality Council hosts regular free online study groups led by Richard Hamilton
- **Mentorship**: Dr. Jackie Graham, who worked closely with Dr. Deming, mentors study groups
- **Local Groups**: Many quality organizations facilitate local study groups

## ♿ Accessibility

Accessibility is a first-class concern in the interactive version. Current features include:

- **Skip-to-content link**: Keyboard and screen-reader users can bypass the sidebar on every page
- **OpenDyslexic font toggle**: Fixed bottom-right button switches body and heading text to the OpenDyslexic typeface; the preference is remembered across sessions via `localStorage`
- **Visible focus indicators**: Keyboard focus is clearly outlined on interactive controls (`:focus-visible`) without affecting mouse users
- **ARIA labelling**: Interactive SVGs (the Funnel Experiment), data tables (cooperation activities), and Observable JS input widgets expose accessible names to assistive technology
- **Live regions**: Status updates in the Funnel Experiment are announced via `aria-live="polite"`
- **Non-colour status indicators**: Funnel-experiment state is conveyed through shape and text as well as colour, meeting WCAG 1.4.1
- **Reduced-motion support**: Animated transitions respect the `prefers-reduced-motion: reduce` media query
- **Print-safe styling**: Decorative controls and colour overrides are suppressed in print media so hard-copy notes render cleanly

If you encounter an accessibility issue, please open a GitHub issue — a11y regressions are treated as bugs.

## 🛠 Technical Requirements

This course is built using:
- **Quarto**: For creating the interactive book
- **R**: For statistical analysis and visualizations
- **HTML/CSS/JavaScript**: For interactive elements

### Local Development
If you want to run this locally:

```bash
# Install R (4.4.0+) and Quarto
# Clone the repository
git clone https://github.com/lddurbin/twelve_days_to_deming.git
cd twelve_days_to_deming

# Restore R dependencies (uses renv for reproducible package management)
Rscript -e 'renv::restore()'

# Preview during development
quarto preview

# Or build the full book
quarto render
```

## 📚 Course Content

### Key Topics Covered
- **System of Profound Knowledge**: Deming's four interrelated areas of knowledge
- **Variation**: Understanding and managing variation in processes
- **Theory of Knowledge**: How we learn and improve
- **Psychology**: Understanding human behavior in organizations
- **Quality Management**: Beyond inspection to prevention
- **Leadership**: The role of management in improvement

### Learning Approach
- **Active participation** through embedded exercises
- **Real-world applications** through projects
- **Reflection and discussion** opportunities
- **Progressive complexity** building from basics to advanced concepts

## 🎓 About the Author

**Henry R. Neave** is a distinguished educator and Deming expert who:
- Attended multiple four-day seminars with Dr. Deming
- Developed and delivered hundreds of seminars on Deming's work
- Authored *The Deming Dimension*
- Spent nearly 20 years teaching Deming's principles at the University of Nottingham
- Received Dr. Deming's permission to use his material extensively
- Received the American Society for Quality's Deming Medal (2001)
- Is an Honorary Fellow of the Chartered Quality Institute

## 🤝 Contributing

This course has benefited from contributions from many experts and practitioners. If you have suggestions for improvements or find issues, please:

1. Check existing issues first
2. Create a new issue with clear description
3. For substantial changes, consider opening a discussion first

### For Developers

The conversion of remaining days from PDF to interactive Quarto follows a structured 5-phase workflow. See [`workflow/CONVERSION_GUIDE.md`](workflow/CONVERSION_GUIDE.md) for the complete reference, including CSS classes, R functions, interactive element templates, and file naming conventions.

## 📄 License

This course is based on Dr. W. Edwards Deming's teachings and is made available for educational purposes. Please respect the intellectual property and use appropriately.

## 🌐 Live Version

The course is available online at: [deming.leedurbin.co.nz](https://deming.leedurbin.co.nz)

## 📞 Support

For questions about the course content or technical issues:
- Check the course materials for guidance
- Review the time management section for study tips
- Consider joining a study group for additional support
- Contact quality organizations like [NZOQ](https://www.nzoq.org.nz/12-days-to-deming) for study group information

---

*"The aim of leadership should be to improve the performance of man and machine, to improve quality, to increase output, and simultaneously to bring pride of workmanship to people."* - W. Edwards Deming 