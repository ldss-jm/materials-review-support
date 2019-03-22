# Alt-access resource identification

## Overview

Take Sierra record list or other title list, find matching title from SerialsSolutions data, and indicate the best (most current) resource for the title.

## General logic

### matching Sierra records

* attempt to match using an ssj/ssib in an 001 and any issns in an 022|a, 022|L, or 776|x. A match is found when any of these match, not necessarily all of them.
* if that fails we try to scrape other good issns from OCLC/worldcat and attempt to match using them.
* if that too fails, we try any 022|y issns from Sierra.

### matching titlelist records (e.g. Wiley)

* we try to match using provided ssj, issn, and eissn
* no oclc scraping or fallback issns

### best resources

* current > embargo > fixed
  * a 100 year embargo is better than fixed end point of 2016.
* In the case of ties, all tying resources are indicated
  * so, when multiple resources are listed in the output data, this is never a list of resources descending by recency. The resources are equally good.
* Comparisons of embargo dates are based on full dates, not the descriptive statement, so the 12/31/16 point would be selected over the 1/1/16 point. Non-JSTOR embargo statements are converted to full dates for comparison. So something that ends “2 years ago” would be compared using an end date of current_date – (2 * 365 days).
* JSTOR enddates in the sersol data are presented as fixed dates, but despite that are taken to be embargos. That's only for JSTOR.
* JSTOR embargo end dates only consider the year. So, in 2017, for a JSTOR access point that ended 12/31/16, 1/1/16, and 12/31/15, the first two would be described as “1 year ago” and the third as “2 years ago.”

## INPUT

Order of fields and casing of field names does not matter.

### Sersol data

A basic data on demand report where SerSol has also included the ssj and ACQ E-resources has added a column indicating whether the resource / access point should be blacklisted.

#### Sersol required fields

* id: contains ssj/ssib
* title, issn, eissn, enddate, resource
* 'include as alt access point?': must be "yes" or "no"

#### Sersol optional fields

* startdate and url come in the standard DoD report but don't get used
* Optional fields don't propagate into the output data.

### Sierra data

Standard Sierra export for order records under review. The issn fields must be separated by subfield. Repeated field delimiter should be a space.

#### Sierra required fields

* '245': title, in any form (e.g. 245, 245|abnp, non-marc title)
* '1': the 001
* '022|a'
* '022|l': that's "ell"
* '022|y'
* '776|x'

#### Sierra optional fields

* Whatever other fields you need.
* These optional fields are included in the output data.

### Titlelist (e.g. Wiley) data

* 'title'
* 'issn': single issn
* 'e-issn': single issn
* 'ssj#': must begin "ss" if it contains an ssj

Note: issn/e-issn are each expected to contain a single issn, because that's what the 2017 Wiley list looked like. If a titlelist instead sometimes/always has fields with delimited lists of issns, that could be accomodated but it should be pointed out and if such titlelists structured the lists in the same fashion (basically, the same delimiting) it would be great.

#### Titlelist optional fields

* Whatever other fields you need.
* These optional fields are included in the output data.

## OUTPUT

Output is divided into two tables, one for "current" resources and one for "non-current" resources (which includes records with no matching alt access).

#### original fields

Unmodified, original Sierra/titlelist data

#### added fields

* matchcount
  * number of ssj titles that matched. Note, distinct from the number of resources
    matched. This should be 0 (no matches) or 1 (for one matching sersol
    title). If it is more than 1, the matches should be examined to determine
    which is the correct match. These "extra_match" cases are initially output
    separately for review and the incorporated back in when matching is fixed.
* bib_identifier_notes:

  any/all of the following that apply:
  * Had no ssj/issn to make match
  * ssj not found in sersol report
  * matched using issns from worldcat lookup
  * matched using 022|y
* all_issns
  * list of issns actually used to attempt matching
  * so, excludes scraped or 022|y issns unless we had to resort to them
  * ' | ' delimited
* matching_ssj
  * ssj/ssib for sersol matching title
* matching_title
  * title for sersol matching title
* best_end_type
  * current > embargo > fixed
* best_end_date
  * one of: "current", a relative end date (e.g. "6 years ago"), or a fixed end date
  (e.g. "1/1/1990")
* best_end_resources
  * resource for the most recent access point
  * where there is a tie for most recent, lists all tying resources ' | ' delimited

## Notes / post-processing

* matches by 022|y should be reviewed
* extra_matches should be reviewed

### 2017 notes

  There were fewer than 10 items that were matched using the 022|y. Some of the matches seemed useful (e.g. b57443282 / Information technology management [serial] was matched up with ssj0034868 / Information management which looks like it was a previous title). Some of the matches might be false positives or otherwise undesirable. It’s probably best if somebody looked over those matches. The 022|y was a last resort, so if the 022|y is bad there was no other match found. The bib_identifier_notes column includes a note when the 022|y was used.

  A few Millennium/Wiley records had “extra matches.” For example, the Sersol report has a set of access points for ssib024312238 / Herald-Sun (Melbourne) and a set of access points for ssj0010891 / herald-sun (Durham, N.C.). On the Sersol report, both sets have an ISSN of 1055-4467, so our b23783060 / Herald Sun ends up matching against both. There are probably about 30 of these Mil/Wiley records total. They are included on the extra_matches sheets and not included on the current/non-current results. The sheets have each problem Mil/Wiley record, with the multiple associated Sersol records appearing below it in descending order of end-date preference. Generally, the first record listed looked like an acceptable match to me. I flagged the four instances where this was not the case with yellow highlighting. If somebody could verify this, it would be nice. I only need to know when the first record is not a correct match.
