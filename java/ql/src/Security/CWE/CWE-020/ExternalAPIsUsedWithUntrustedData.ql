/**
 * @name Frequency counts for external APIs which are used with untrusted data
 * @description This reports the external APIs which are used with untrusted data, along with how
 *              frequently the API is called, and how many unique sources of untrusted data flow
 *              to it.
 * @id java/count-untrusted-data-external-api
 * @kind table
 */

import java
import semmle.code.java.security.ExternalAPIs::ExternalAPIs
import semmle.code.java.dataflow.DataFlow

from ExternalAPIUsedWithUntrustedData externalAPI
select externalAPI, count(externalAPI.getUntrustedDataNode()) as numberOfUses,
  externalAPI.getNumberOfUntrustedSources() as numberOfUntrustedSources order by
    numberOfUntrustedSources desc
